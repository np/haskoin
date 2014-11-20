FROM quay.io/np__/haskell

MAINTAINER Nicolas Pouillard [https://nicolaspouillard.fr]

ADD     haskoin.cabal /haskoin/haskoin.cabal
WORKDIR /haskoin
RUN     cabal update && cabal install --dependencies-only
ADD     . /haskoin
RUN     cabal install
