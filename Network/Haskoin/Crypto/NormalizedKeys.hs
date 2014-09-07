module Network.Haskoin.Crypto.NormalizedKeys
( MasterKey(..)
, AccPrvKey(..)
, AccPubKey(..)
, AddrPrvKey(..)
, AddrPubKey(..)
, KeyIndex
, makeMasterKey
, loadMasterKey
, loadPrvAcc
, loadPubAcc
, addr
, accPrvKey
, accPubKey
, extPrvKey
, extPubKey
, intPrvKey
, intPubKey
, accPrvKeys
, accPubKeys
, extPrvKeys
, extPubKeys
, intPrvKeys
, intPubKeys
, extAddr
, intAddr
, extAddrs
, intAddrs
, extAddrs'
, intAddrs'
, extMulSigKey
, intMulSigKey
, extMulSigKeys
, intMulSigKeys
, extMulSigAddr
, intMulSigAddr
, extMulSigAddrs
, intMulSigAddrs
) where

import Control.DeepSeq (NFData, rnf)
import Control.Monad (guard)
import Control.Applicative ((<$>))

import Data.Word (Word32)
import Data.Maybe (fromJust, isJust)
import qualified Data.ByteString as BS (ByteString)

import Network.Haskoin.Crypto.ExtendedKeys
import Network.Haskoin.Crypto.Base58
import Network.Haskoin.Script.Parser

type KeyIndex = Word32

-- | Data type representing an extended private key at the root of the
-- derivation tree. Master keys have depth 0 and no parents. They are
-- represented as m\/ in BIP32 notation.
newtype MasterKey = MasterKey { masterKey :: XPrvKey }
    deriving (Eq, Show, Read)

instance NFData MasterKey where
    rnf (MasterKey m) = rnf m

-- | Data type representing a private account key. Account keys are generated
-- from a 'MasterKey' through prime derivation. This guarantees that the
-- 'MasterKey' will not be compromised if the account key is compromised. 
-- 'AccPrvKey' is represented as m\/i'\/ in BIP32 notation.
newtype AccPrvKey = AccPrvKey { getAccPrvKey :: XPrvKey }
    deriving (Eq, Show, Read)

instance NFData AccPrvKey where
    rnf (AccPrvKey k) = rnf k

-- | Data type representing a public account key. It is computed through
-- derivation from an 'AccPrvKey'. It can not be derived from the 'MasterKey'
-- directly (property of prime derivation). It is represented as M\/i'\/ in
-- BIP32 notation. 'AccPubKey' is used for generating receiving payment
-- addresses without the knowledge of the 'AccPrvKey'.
newtype AccPubKey = AccPubKey { getAccPubKey :: XPubKey }
    deriving (Eq, Show, Read)

instance NFData AccPubKey where
    rnf (AccPubKey k) = rnf k

-- | Data type representing a private address key. Private address keys are
-- generated through a non-prime derivation from an 'AccPrvKey'. Non-prime
-- derivation is used so that the public account key can generate the receiving
-- payment addresses without knowledge of the private account key. 'AccPrvKey'
-- is represented as m\/i'\/0\/j\/ in BIP32 notation if it is a regular
-- receiving address. Internal (change) addresses are represented as
-- m\/i'\/1\/j\/. Non-prime subtree 0 is used for regular receiving addresses
-- and non-prime subtree 1 for internal (change) addresses.
newtype AddrPrvKey = AddrPrvKey { getAddrPrvKey :: XPrvKey }
    deriving (Eq, Show, Read)

instance NFData AddrPrvKey where
    rnf (AddrPrvKey k) = rnf k

-- | Data type representing a public address key. They are generated through
-- non-prime derivation from an 'AccPubKey'. This is a useful feature for
-- read-only wallets. They are represented as M\/i'\/0\/j in BIP32 notation
-- for regular receiving addresses and by M\/i'\/1\/j for internal (change)
-- addresses.
newtype AddrPubKey = AddrPubKey { getAddrPubKey :: XPubKey }
    deriving (Eq, Show, Read)

instance NFData AddrPubKey where
    rnf (AddrPubKey k) = rnf k

-- | Create a 'MasterKey' from a seed.
makeMasterKey :: BS.ByteString -> Maybe MasterKey
makeMasterKey bs = MasterKey <$> makeXPrvKey bs

-- | Load a 'MasterKey' from an 'XPrvKey'. This function will fail if the
-- extended private key does not have the properties of a 'MasterKey'.
loadMasterKey :: XPrvKey -> Maybe MasterKey
loadMasterKey k
    | xPrvDepth  k == 0 && 
      xPrvParent k == 0 && 
      xPrvIndex  k == 0 = Just $ MasterKey k
    | otherwise         = Nothing

-- | Load a private account key from an 'XPrvKey'. This function will fail if
-- the extended private key does not have the properties of a 'AccPrvKey'.
loadPrvAcc :: XPrvKey -> Maybe AccPrvKey
loadPrvAcc k
    | xPrvDepth k == 1 &&
      xPrvIsPrime k    = Just $ AccPrvKey k
    | otherwise        = Nothing

-- | Load a public account key from an 'XPubKey'. This function will fail if
-- the extended public key does not have the properties of a 'AccPubKey'.
loadPubAcc :: XPubKey -> Maybe AccPubKey
loadPubAcc k
    | xPubDepth k == 1 &&
      xPubIsPrime k    = Just $ AccPubKey k
    | otherwise        = Nothing

-- | Computes an 'AccPrvKey' from a 'MasterKey' and a derivation index.
accPrvKey :: MasterKey -> KeyIndex -> Maybe AccPrvKey
accPrvKey (MasterKey par) i = AccPrvKey <$> (f =<< primeSubKey par i)
    where f k = guard (isJust $ prvSubKey k 0) >>
                guard (isJust $ prvSubKey k 1) >>
                return k

-- | Computes an 'AccPubKey' from a 'MasterKey' and a derivation index.
accPubKey :: MasterKey -> KeyIndex -> Maybe AccPubKey
accPubKey (MasterKey par) i = f <$> primeSubKey par i
    where f = AccPubKey . deriveXPubKey

-- | Computes an external 'AddrPrvKey' from an 'AccPrvKey' and a derivation
-- index.
extPrvKey :: AccPrvKey -> KeyIndex -> Maybe AddrPrvKey
extPrvKey (AccPrvKey par) i = AddrPrvKey <$> prvSubKey extKey i
    where extKey = fromJust $ prvSubKey par 0

-- | Computes an external 'AddrPubKey' from an 'AccPubKey' and a derivation
-- index.
extPubKey :: AccPubKey -> KeyIndex -> Maybe AddrPubKey
extPubKey (AccPubKey par) i = AddrPubKey <$> pubSubKey extKey i
    where extKey = fromJust $ pubSubKey par 0

-- | Computes an internal 'AddrPrvKey' from an 'AccPrvKey' and a derivation
-- index.
intPrvKey :: AccPrvKey -> KeyIndex -> Maybe AddrPrvKey
intPrvKey (AccPrvKey par) i = AddrPrvKey <$> prvSubKey intKey i
    where intKey = fromJust $ prvSubKey par 1

-- | Computes an internal 'AddrPubKey' from an 'AccPubKey' and a derivation
-- index.
intPubKey :: AccPubKey -> KeyIndex -> Maybe AddrPubKey
intPubKey (AccPubKey par) i = AddrPubKey <$> pubSubKey intKey i
    where intKey = fromJust $ pubSubKey par 1 -- THESE fromJust could be avoided

-- | Cyclic list of all valid 'AccPrvKey' derived from a 'MasterKey' and
-- starting from an offset index.
accPrvKeys :: MasterKey -> KeyIndex -> [(AccPrvKey,KeyIndex)]
accPrvKeys = subKeys . accPrvKey

-- | Cyclic list of all valid 'AccPubKey' derived from a 'MasterKey' and
-- starting from an offset index.
accPubKeys :: MasterKey -> KeyIndex -> [(AccPubKey,KeyIndex)]
accPubKeys = subKeys . accPubKey

-- | Cyclic list of all valid external 'AddrPrvKey' derived from a 'AccPrvKey'
-- and starting from an offset index.
extPrvKeys :: AccPrvKey -> KeyIndex -> [(AddrPrvKey,KeyIndex)]
extPrvKeys = subKeys . extPrvKey

-- | Cyclic list of all valid external 'AddrPubKey' derived from a 'AccPubKey'
-- and starting from an offset index.
extPubKeys :: AccPubKey -> KeyIndex -> [(AddrPubKey,KeyIndex)]
extPubKeys = subKeys . extPubKey

-- | Cyclic list of all internal 'AddrPrvKey' derived from a 'AccPrvKey' and
-- starting from an offset index.
intPrvKeys :: AccPrvKey -> KeyIndex -> [(AddrPrvKey,KeyIndex)]
intPrvKeys = subKeys . intPrvKey

-- | Cyclic list of all internal 'AddrPubKey' derived from a 'AccPubKey' and
-- starting from an offset index.
intPubKeys :: AccPubKey -> KeyIndex -> [(AddrPubKey,KeyIndex)]
intPubKeys = subKeys . intPubKey

{- Generate addresses -}

-- | Computes an 'Address' from an 'AddrPubKey'.
addr :: AddrPubKey -> Address
addr = xPubAddr . getAddrPubKey

-- | Computes an external address from an 'AccPubKey' and a 
-- derivation index.
extAddr :: AccPubKey -> KeyIndex -> Maybe Address
extAddr a i = addr <$> extPubKey a i

-- | Computes an internal addres from an 'AccPubKey' and a 
-- derivation index.
intAddr :: AccPubKey -> KeyIndex -> Maybe Address
intAddr a i = addr <$> intPubKey a i

-- | Cyclic list of all external addresses derived from a 'AccPubKey'
-- and starting from an offset index.
extAddrs :: AccPubKey -> KeyIndex -> [(Address,KeyIndex)]
extAddrs = subKeys . extAddr

-- | Cyclic list of all internal addresses derived from a 'AccPubKey'
-- and starting from an offset index.
intAddrs :: AccPubKey -> KeyIndex -> [(Address,KeyIndex)]
intAddrs = subKeys . intAddr

-- | Same as 'extAddrs' with the list reversed.
extAddrs' :: AccPubKey -> KeyIndex -> [(Address,KeyIndex)]
extAddrs' = subKeys' . extAddr

-- | Same as 'intAddrs' with the list reversed.
intAddrs' :: AccPubKey -> KeyIndex -> [(Address,KeyIndex)]
intAddrs' = subKeys' . intAddr

{- MultiSig -}

-- | Computes a list of external 'AddrPubKey' from an 'AccPubKey', a list
-- of thirdparty multisig keys and a derivation index. This is useful for 
-- computing the public keys associated with a derivation index for
-- multisig accounts.
extMulSigKey :: AccPubKey -> [XPubKey] -> KeyIndex -> Maybe [AddrPubKey]
extMulSigKey a ps i = (map AddrPubKey) <$> mulSigSubKey keys i
    where keys = map (fromJust . (flip pubSubKey 0)) $ (getAccPubKey a) : ps

-- | Computes a list of internal 'AddrPubKey' from an 'AccPubKey', a list
-- of thirdparty multisig keys and a derivation index. This is useful for 
-- computing the public keys associated with a derivation index for
-- multisig accounts.
intMulSigKey :: AccPubKey -> [XPubKey] -> KeyIndex -> Maybe [AddrPubKey]
intMulSigKey a ps i = (map AddrPubKey) <$> mulSigSubKey keys i
    where keys = map (fromJust . (flip pubSubKey 1)) $ (getAccPubKey a) : ps

-- | Cyclic list of all external multisignature 'AddrPubKey' derivations 
-- starting from an offset index.
extMulSigKeys :: AccPubKey -> [XPubKey] -> KeyIndex -> [([AddrPubKey],KeyIndex)]
extMulSigKeys a ps = subKeys (extMulSigKey a ps)

-- | Cyclic list of all internal multisignature 'AddrPubKey' derivations
-- starting from an offset index.
intMulSigKeys :: AccPubKey -> [XPubKey] -> KeyIndex -> [([AddrPubKey],KeyIndex)]
intMulSigKeys a ps = subKeys (intMulSigKey a ps)

-- | Computes an external multisig address from an 'AccPubKey', a
-- list of thirdparty multisig keys and a derivation index.
extMulSigAddr :: AccPubKey -> [XPubKey] -> Int -> KeyIndex -> Maybe Address
extMulSigAddr a ps r i = do
    xs <- (map (xPubKey . getAddrPubKey)) <$> extMulSigKey a ps i
    return $ scriptAddr $ sortMulSig $ PayMulSig xs r

-- | Computes an internal multisig address from an 'AccPubKey', a
-- list of thirdparty multisig keys and a derivation index.
intMulSigAddr :: AccPubKey -> [XPubKey] -> Int -> KeyIndex -> Maybe Address
intMulSigAddr a ps r i = do
    xs <- (map (xPubKey . getAddrPubKey)) <$> intMulSigKey a ps i
    return $ scriptAddr $ sortMulSig $ PayMulSig xs r

-- | Cyclic list of all external multisig addresses derived from
-- an 'AccPubKey' and a list of thirdparty multisig keys. The list starts
-- at an offset index.
extMulSigAddrs :: AccPubKey -> [XPubKey] -> Int -> KeyIndex 
              -> [(Address,KeyIndex)]
extMulSigAddrs a ps r = subKeys (extMulSigAddr a ps r)

-- | Cyclic list of all internal multisig addresses derived from
-- an 'AccPubKey' and a list of thirdparty multisig keys. The list starts
-- at an offset index.
intMulSigAddrs :: AccPubKey -> [XPubKey] -> Int -> KeyIndex 
              -> [(Address,KeyIndex)]
intMulSigAddrs a ps r = subKeys (intMulSigAddr a ps r)

