{-|
  This package provides basic types used for the Bitcoin networking protocol
  together with Data.Binary instances for efficiently serializing and
  de-serializing them. More information on the bitcoin protocol is available
  here: <http://en.bitcoin.it/wiki/Protocol_specification>
-}
module Network.Haskoin.Node
( 
  -- * Requesting data
  GetData(..)
, Inv(..)
, InvVector(..)
, InvType(..)
, NotFound(..)

  -- * Network types
, VarInt(..)
, VarString(..)
, NetworkAddress(..)
, Addr(..)
, NetworkAddressTime
, Version(..)
, Ping(..)
, Pong(..)
, Alert(..)
, Reject(..)
, RejectCode(..)
, reject

  -- * Messages
, Message(..)
, MessageHeader(..)
, MessageCommand(..)

  -- * Bloom filters
, BloomFlags(..)
, BloomFilter(..)
, FilterLoad(..)
, FilterAdd(..)
, bloomCreate
, bloomInsert
, bloomContains
, isBloomValid
, isBloomEmpty
, isBloomFull

   -- * Peer
, newPeerSession
, startPeer
 
   -- * Peer Manager
, withPeerManager  
, RemoteHost(..)

   -- * SPV Blockchain
, withSpvBlockChain
, DecodedMerkleBlock(..)

   -- * SPV Mempool & Node
, withSpvNode
, withSpvMempool
, WalletMessage(..)
, NodeRequest(..)

) where

import Network.Haskoin.Node.Message
import Network.Haskoin.Node.Types
import Network.Haskoin.Node.Bloom
import Network.Haskoin.Node.Chan
import Network.Haskoin.Node.Peer
import Network.Haskoin.Node.PeerManager
import Network.Haskoin.Node.SpvBlockChain
import Network.Haskoin.Node.SpvMempool

