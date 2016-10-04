# 0.1.0.1

* Made exception handling for exceptions from the network package a little
  more robust. Exceptions from the network package is just strings, and
  matching of errors need to be done by string matching. If a string is
  changing the exception handler can fail. Added substring matching to
  better handle this case.

* Fixing a documentation bug.

# 0.1.0.0

* Initial release of hats - NATS client for Haskell.

  The hats library provides client access for Haskell applications
  using the NATS messaging system [https://nats.io](https://nats.io).

  A few examples can be found in [https://github.com/kosmoskatten/hats/blob/master/example/Examples.hs](https://github.com/kosmoskatten/hats/blob/master/example/Examples.hs).
