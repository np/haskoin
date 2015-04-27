FROM haskell:7.8

MAINTAINER Nicolas Pouillard [https://nicolaspouillard.fr]

ADD     haskoin.cabal /haskoin/haskoin.cabal
WORKDIR /haskoin
RUN     apt-get update && apt-get install -y libleveldb-dev libzmq3-dev libsnappy-dev
RUN     cabal update && cabal install --dependencies-only --enable-tests
ADD     . /haskoin
RUN     cabal install --global
RUN     cabal test || echo "The tests failed!"
