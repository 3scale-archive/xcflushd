## [1.1.0] - 2017-05-02
- Switched from MRI to JRuby. our tests show that JRuby performs better than
  MRI when there is a high number of calls to be made to 3scale's backend in a
  flushing cycle. One of the reasons is that JRuby allows us to make several
  calls to 3scale's backend in parallel as well as parse their XML responses.
- Updated dependencies: 3scale_client (2.11.0), gli (2.16.0), redis(3.3.3),
  concurrent-ruby(1.0.5), simplecov (0.14.1), rubocop (0.48.1).
- Changed the timezone in the Dockerfile to UTC. This way, timestamps can be
  easily translated from log files or other sources to whatever is needed.
- Increased the number of messages that the priority auth renewer can process
  at the same time. We accomplished that by reducing the waiting times between
  publishing attempts. Those waiting times were unnecessarily long.
- Fixed a bug that affected the way thread pools were being used. We were using
  concurrent-ruby's ThreadPoolExecutor without specifying a max size for the
  queue, and that type of pool only spawns a new thread when the queue is full.
  That means that in practice, we specified a 'min:max' number of threads, but
  only min were spawned. Now we are using FixedThreadPools and always take
  the max number of threads for the input, ignoring the min.
- Added logging that shows the run time of each of the 5 phases of a
  flushing cycle: 1- getting the reports from Redis, 2- reporting to 3scale,
  3- waiting to leave some time to the reports to take effect, 4- getting the
  auths from 3scale, 5- renewing the auths in Redis. This is useful for
  debugging purposes.
- Minor changes in the Dockerfile to make it run on CentOS / RHEL.
- Improved performance of the flushing phase that takes care of renewing
  authorizations in Redis by using the hmset command.
