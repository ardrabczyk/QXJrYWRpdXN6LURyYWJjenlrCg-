===============
What is this?
===============

Simple REST service written in Python 3 for learning purposes.  It
continuously downloads data from the specified URLs at the specified
intervals, saves downloaded data to the Redis store and allows user to
modify download intervals of existing URLs and remove URLs and
downloaded data.

How to use it?
==============

Service runs on port 8080 and provides several endpoints that work
with different HTTP methods. Data is exchanged in JSON.

Add a new URL to download data from with a specified interval (in
seconds) or update interval of an existing URL and get its ID number
that will be used with other endpoints:

::

   $ curl -si 127.0.0.1:8080/api/fetcher -X POST -d '{"url":"https://httpbin.org/range/6","interval":4}'
   HTTP/1.1 200 OK
   Connection: keep-alive
   Keep-Alive: 5
   Content-Length: 9
   Content-Type: text/plain; charset=utf-8

   {"id": 1}


Error is returned in case of malformed URL or malformed JSON:

::

   $ curl -si 127.0.0.1:8080/api/fetcher -X POST -d '{"url":"https//httpbin.org/range/15","interval":2}'
   HTTP/1.1 400 Bad Request
   Connection: keep-alive
   Keep-Alive: 5
   Content-Length: 16
   Content-Type: text/plain

   Malformatted URL
   $ curl -si 127.0.0.1:8080/api/fetcher -X POST -d '{"url":"https//httpbin.org/range/15","interval":2}}'
   HTTP/1.1 400 Bad Request
   Connection: keep-alive
   Keep-Alive: 5
   Content-Length: 39
   Content-Type: text/plain; charset=utf-8

   Error: Failed when parsing body as json
   $ curl -si 127.0.0.1:8080/api/fetcher -X POST -d '{"url":"https://httpbin.org/range/15","interval":"2"}'
   HTTP/1.1 400 Bad Request
   Connection: keep-alive
   Keep-Alive: 5
   Content-Length: 27
   Content-Type: text/plain

   Interval cannot be a string

If URL that has been already added before is used the same ID will be returned in the response:

::

   $ curl -si 127.0.0.1:8080/api/fetcher -X POST -d '{"url":"https://httpbin.org/range/6","interval":10}'
   HTTP/1.1 200 OK
   Connection: keep-alive
   Keep-Alive: 5
   Content-Length: 9
   Content-Type: text/plain; charset=utf-8

   {"id": 1}

Trailing slashes in URLs are ignored so that this:

::

   $ curl -si 127.0.0.1:8080/api/fetcher -X POST -d '{"url":"https://httpbin.org/range/7/","interval":10}'
   HTTP/1.1 200 OK
   Connection: keep-alive
   Keep-Alive: 5
   Content-Length: 9
   Content-Type: text/plain; charset=utf-8

   {"id": 2}

is the same as this:

::

   $ curl -si 127.0.0.1:8080/api/fetcher -X POST -d '{"url":"https://httpbin.org/range/7","interval":10}'
   HTTP/1.1 200 OK
   Connection: keep-alive
   Keep-Alive: 5
   Content-Length: 9
   Content-Type: text/plain; charset=utf-8

   {"id": 2}


Maximum payload size accepted by the service is 1 megabyte, that is
1000 bytes, not 1024 bytes as in mebibyte:

::

   $ curl -si 127.0.0.1:8080/api/fetcher -X POST -d '{"url":"https//httpbin.org/range/15","interval":60oeueoouaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa}'
   HTTP/1.1 413 Request Entity Too Large
   Connection: close
   Content-Length: 24
   Content-Type: text/plain; charset=utf-8

   Error: Payload Too Large

Download timeout is set to 5 seconds. In case of timeout `null` is
written to the response field.  Get a history of data downloaded from
the given URL by referring to it by its ID:

::

   $ curl -si 127.0.0.1:8080/api/fetcher/1/history
   HTTP/1.1 200 OK
   Connection: keep-alive
   Keep-Alive: 5
   Content-Length: 353
   Content-Type: text/plain; charset=utf-8

   [
      {
	 "response": "abcdefg",
	 "duration": 0.5514349937438965,
	 "created_at": 1569180511.8400853
      },
      {
	 "response": "abcdefg",
	 "duration": 0.5317299365997314,
	 "created_at": 1569180523.9480026
      },
      {
	 "response": "abcdefg",
	 "duration": 0.5266106128692627,
	 "created_at": 1569180533.9429138
      }

List all saved URLs:

::

   $ curl -si 127.0.0.1:8080/api/fetcher/
   HTTP/1.1 200 OK
   Connection: keep-alive
   Keep-Alive: 5
   Content-Length: 130
   Content-Type: text/plain; charset=utf-8

   [{"id": 1, "url": "https://httpbin.org/range/7", "interval": 10},
   {"id": 2, "url": "https://httpbin.org/range/8", "interval": 10}]


Stop downloading data from the given URL and delete history of
data downloaded from the given URL:

::

   $ curl -si 127.0.0.1:8080/api/fetcher/1 -X DELETE
   HTTP/1.1 200 OK
   Connection: keep-alive
   Keep-Alive: 5
   Content-Length: 9
   Content-Type: text/plain; charset=utf-8

   {"id": 1}

Installation
============

Build Docker image:

::

   docker build -t simple-rest-service .

Start service in Docker container:

::

   docker run --rm -p 8080:8080 simple-rest-service

Tests
============

Change to `tests` and run:

::

   ./test.sh  ../conf
