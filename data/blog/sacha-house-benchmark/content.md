Out of curiosity, I ran an HTTP performance benchmark on my website (locally).  
I used [https://github.com/hatoo/oha](https://github.com/hatoo/oha "https://github.com/hatoo/oha"), a CLI tool to run HTTP load tests. I ran the tests by directly calling the raw HTTP endpoints @ `http://localhost:6969/projects`, without going through NGINX or anything.

Here are the results :

```
❯ oha -z 30s  http://127.0.0.1:6969/projects
Summary:
  Success rate: 100.00%
  Total:        30001.6334 ms
  Slowest:      48.3993 ms
  Fastest:      0.4083 ms
  Average:      4.7062 ms
  Requests/sec: 10616.3886

  Total data:   36.32 GiB
  Size/request: 119.59 KiB
  Size/sec:     1.21 GiB

Response time histogram:
   0.408 ms [1]      |
   5.207 ms [220176] |■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■■
  10.007 ms [84447]  |■■■■■■■■■■■■
  14.806 ms [11651]  |■
  19.605 ms [1772]   |
  24.404 ms [352]    |
  29.203 ms [37]     |
  34.002 ms [18]     |
  38.801 ms [2]      |
  43.600 ms [0]      |
  48.399 ms [3]      |

Response time distribution:
  10.00% in 2.3039 ms
  25.00% in 3.0365 ms
  50.00% in 4.0380 ms
  75.00% in 5.7530 ms
  90.00% in 7.9202 ms
  95.00% in 9.6476 ms
  99.00% in 13.7741 ms
  99.90% in 20.2472 ms
  99.99% in 27.1212 ms


Details (average, fastest, slowest):
  DNS+dialup:   0.3275 ms, 0.0676 ms, 0.6415 ms
  DNS-lookup:   0.0021 ms, 0.0012 ms, 0.0144 ms

Status code distribution:
  [200] 318459 responses

Error distribution:
  [50] aborted due to deadline
```

# **10 616 req/s** !

Pretty good ! Keep in mind that this website is running on a pretty old machine. Keeping that in mind, I'm pretty happy with those results.

The server this site is running on is configured with:

*   OS: Debian GNU/Linux bookworm 12.12 x86\_64
    
*   Kernel: 6.12.57+deb12-amd64
    
*   CPU: Intel(R) Core(TM) i5-8500 (6) @ 4.10 GHz
    
*   GPU: Intel UHD Graphics 630 @ 1.10 GHz \[Integrated\]
    
*   Memory: 14.98 GiB (16GB)
    

So nothing fancy.

## Appendix

Here are some other useful tools I found while searching :

*   [wg/wrk: Modern HTTP benchmarking tool](https://github.com/wg/wrk "https://github.com/wg/wrk")
    
*   [sharkdp/hyperfine: A command-line benchmarking tool](https://github.com/sharkdp/hyperfine "https://github.com/sharkdp/hyperfine")
