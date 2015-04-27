FROM haskell:7.8

MAINTAINER Nicolas Pouillard [https://nicolaspouillard.fr]

ADD     haskoin.cabal /haskoin/haskoin.cabal
WORKDIR /haskoin
RUN     apt-get update && apt-get install -y libleveldb-dev libzmq3-dev libsnappy-dev
ADD     https://www.stackage.org/lts/cabal.config cabal.config
RUN     cabal update && cabal install --dependencies-only --enable-tests
ADD     . /haskoin
RUN     cabal build
RUN     cabal install --only --global
RUN     cabal test || echo "The tests failed!"
