#!/usr/bin/env python3
# -*- coding: utf-8 -*-"

import json
import re
import urllib.request
import time
from sanic import Sanic
from sanic import response
from sanic.views import HTTPMethodView
from sanic.response import text
import multitimer
import redis
import validators

app = Sanic(__name__)


class Redis():
    """
    Redis wrapper

    As we have to identify elements in the database by both URL string
    in case of POST method and ID number in case DELETE and GET
    methods we use store intermediate hashes with ID keys that point
    to the ID hashes that have repeated URL string and interval. For example:

    127.0.0.1:6379> HGETALL "https://httpbin.org/range/6"
    1) "id"
    2) "2"
    127.0.0.1:6379> HGETALL 2
    1) "url"
    2) "https://httpbin.org/range/6"
    3) "interval"
    4) "4"

    History of fetched data is stored in history:id lists.
    """

    def __init__(self):
        self._db_connection = redis.Redis()
        self._cur_id = 0

    def get_id_from_url(self, url):
        return self._db_connection.hmget(url, "id")[0]

    def delete_id(self, id_to_delete):
        url_key = self._db_connection.hmget(id_to_delete, "url")[0]
        if url_key is None:
            return None

        list_name = "history" + ":" + id_to_delete
        # delete history and 2 keys
        self._db_connection.delete(list_name)
        self._db_connection.delete(url_key)
        self._db_connection.delete(id_to_delete)
        return id_to_delete

    def add_url(self, url, interval):
        # ideally, we should look for a free bucket here
        self._cur_id += 1
        self._db_connection.hset(self._cur_id, mapping={"url": url,
                                                        "interval": interval})
        self._db_connection.hset(url, mapping={"id": self._cur_id})
        return self._cur_id

    def add_fetch_record(self, url, add_response, duration):
        # get ID for site
        redis_id = self._db_connection.hmget(url, "id")[0]
        list_name = "history" + ":" + redis_id.decode("utf-8")
        record_dict = {"response": add_response, "duration": duration,
                       "created_at": time.time()}
        data_j = json.dumps(record_dict)
        self._db_connection.rpush(list_name, data_j)

    def update_interval(self, record_id, new_interval):
        self._db_connection.hset(record_id, "interval", new_interval)

    def dump_fetch_history(self, record_id):
        list_name = "history" + ":" + record_id
        records_list = []
        for i in range(0, self._db_connection.llen(list_name)):
            data = json.loads(self._db_connection.lindex(list_name, i)
                              .decode("utf-8"))
            records_list.append(data)
        return records_list

    def dump_all_urls(self):
        urls_list = []
        for i in range(1, self._cur_id + 1):
            url_key = self._db_connection.hmget(i, "url")[0]
            if url_key is not None:
                unidict = {}
                unidict["id"] = i
                unidict.update({k.decode('utf8'): v.decode('utf8') for
                                k, v in
                                self._db_connection.hgetall(i).items()})
                unidict["interval"] = int(unidict["interval"])
                urls_list.append(unidict)

        return urls_list


class Service(HTTPMethodView):

    @staticmethod
    def get(request):
        all_urls = r.dump_all_urls()

        if not all_urls:
            return text("[]")

        output_json = "["
        for i in all_urls:
            output_json += json.dumps(i)
            output_json += ',\n'

        output_json = output_json[:-2]
        output_json += "]"
        return text(output_json)

    @staticmethod
    def worker_func(site, interval):
        start = time.time()
        try:
            contents = urllib.request.urlopen(site, timeout=5)
        except Exception:
            worker_response = None
            end = time.time()
            worker_response = None
        else:
            end = time.time()
            worker_response = contents.read().decode("utf-8")

        duration = end - start

        r.add_fetch_record(site, worker_response, duration)

    def post(self, request):
        requested_interval = request.json.get('interval')
        requested_url = request.json.get('url')

        try:
            if validators.url(requested_url) is not True:
                return response.HTTPResponse(body="Malformatted URL",
                                             status=400)
        except TypeError:
            return response.HTTPResponse(body="URL is not a string",
                                         status=400)

        try:
            if requested_interval < 1:
                return response.HTTPResponse(body="Interval smaller than 1",
                                             status=400)
        except TypeError:
            return response.HTTPResponse(body="Interval cannot be a string",
                                         status=400)

        # remove trailing / from URL
        requested_url = re.sub(r"/+$", "", requested_url)

        # check if we have this url registered in redis
        redis_id = r.get_id_from_url(requested_url)
        if redis_id is None:
            redis_id = r.add_url(requested_url, requested_interval)
            worker_input = {'site': requested_url, 'interval':
                            requested_interval}
            rpt = multitimer.RepeatingTimer(interval=requested_interval,
                                            function=self.worker_func,
                                            kwargs=worker_input,
                                            count=-1, runonstart=False)
            rpt.start()
            timers_table[redis_id] = rpt
        else:
            redis_id = int(redis_id.decode("utf-8"))
            r.update_interval(redis_id, requested_interval)
            timers_table[redis_id].stop()
            worker_input = {'site': requested_url, 'interval':
                            requested_interval}
            rpt = multitimer.RepeatingTimer(interval=requested_interval,
                                            function=self.worker_func,
                                            kwargs=worker_input,
                                            count=-1,
                                            runonstart=False)
            rpt.start()
            timers_table[redis_id] = rpt

        return text("{\"id\": %s}" % redis_id)


class ServiceAlter(HTTPMethodView):
    @staticmethod
    def delete(request, record_id):
        if int(record_id) in timers_table:
            timers_table[int(record_id)].stop()
            del timers_table[int(record_id)]

        redis_id = r.delete_id(record_id)
        if redis_id is None:
            return response.HTTPResponse(body="ID not found", status=404)

        return text("{\"id\": %s}" % redis_id)

    @staticmethod
    def get(request, record_id):
        return response.HTTPResponse(status=400)


class ServiceAlter1(HTTPMethodView):
    @staticmethod
    def get(request, record_id):
        if str.isdigit(record_id) is False:
            return response.HTTPResponse(status=400)

        if int(record_id) not in timers_table:
            return response.HTTPResponse(body="ID not found", status=404)
        record_list = r.dump_fetch_history(record_id)
        output_json = json.dumps(record_list, indent=3)
        return text(output_json)


if __name__ == '__main__':
    r = Redis()
    timers_table = {}
    reusable_ids = ()

    app.config.update_config("/app/conf.py")
    print("REQUEST_MAX_SIZE: ", app.config.REQUEST_MAX_SIZE)
    print("PORT: ", app.config.PORT)
    print("ENDPOINT_BASE_ADDRESS: ", app.config.ENDPOINT_BASE_ADDRESS)
    app.add_route(Service.as_view(), '/' + app.config.ENDPOINT_BASE_ADDRESS)
    app.add_route(ServiceAlter.as_view(),
                  '/' + app.config.ENDPOINT_BASE_ADDRESS + '/<record_id>')
    app.add_route(ServiceAlter1.as_view(),
                  '/' + app.config.ENDPOINT_BASE_ADDRESS +
                  '/<record_id>/history')
    app.run(host="0.0.0.0", port=app.config.PORT)
