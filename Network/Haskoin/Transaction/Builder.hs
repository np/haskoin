{-# LANGUAGE Trustworthy #-}
{-# LANGUAGE OverloadedStrings #-}
module Network.Haskoin.Transaction.Builder 
( Coin(..)
, buildTx
, buildAddrTx
, SigInput(..)
, signTx
, signInput
, detSignTx
, detSignInput
, verifyStdTx
, verifyStdInput
, guessTxSize
, chooseCoins
, chooseMSCoins
, getFee
, getMSFee
) where

import safe Control.Applicative ((<$>),(<*>))
import safe Control.Monad (mzero, foldM)
import safe Control.Monad.Trans (lift)
import safe Control.Monad.Trans.Either (EitherT, left)
import safe Control.DeepSeq (NFData, rnf)

import safe Data.Maybe (catMaybes, maybeToList, isJust, fromJust, isNothing)
import safe Data.List (sortBy, find, nub)
import safe Data.Word (Word64)
import safe qualified Data.ByteString as BS (length, replicate, empty)
import {-unsafe-} Data.Aeson
    ( Value (Object)
    , FromJSON
    , ToJSON
    , (.=), (.:), (.:?)
    , object
    , parseJSON
    , toJSON
    )

import safe Network.Haskoin.Util
import safe Network.Haskoin.Crypto
import safe Network.Haskoin.Protocol
import safe Network.Haskoin.Script

-- | A Coin is an output of a transaction that can be spent by another
-- transaction. 
data Coin = 
    Coin { coinValue    :: !Word64               -- ^ Value in satoshi
         , coinScript   :: !ScriptOutput         -- ^ Output script
         , coinOutPoint :: !OutPoint             -- ^ Previous outpoint
         , coinRedeem   :: !(Maybe RedeemScript) -- ^ Redeem script
         } deriving (Eq, Show, Read)

instance ToJSON Coin where
    toJSON (Coin v s o r) = object
      [ "value"     .= v
      , "script"    .= s
      , "outpoint"  .= o
      , "redeem"    .= r
      ]

instance FromJSON Coin where
    parseJSON (Object o) =
        Coin <$> o .: "value"
             <*> o .: "script"
             <*> o .: "outpoint"
             <*> o .: "redeem"
    parseJSON _ = mzero

instance NFData Coin where
    rnf (Coin v s o r) = rnf v `seq` rnf s `seq` rnf o `seq` rnf r

-- | Coin selection algorithm for normal (non-multisig) transactions. This
-- function returns the selected coins together with the amount of change to
-- send back to yourself, taking the fee into account.
chooseCoins :: Word64 -- ^ Target price to pay.
            -> Word64 -- ^ Fee price per 1000 bytes.
            -> [Coin] -- ^ List of coins to choose from.
            -> Either String ([Coin],Word64) 
               -- ^ Coin selection result and change amount.
chooseCoins target kbfee xs 
    | target > 0 = maybeToEither err $ greedyAdd target (getFee kbfee) xs
    | otherwise  = Left "chooseCoins: Target must be > 0"
    where err = "chooseCoins: No solution found"

-- | Coin selection algorithm for multisignature transactions. This function
-- returns the selected coins together with the amount of change to send back
-- to yourself, taking the fee into account. This function assumes all the 
-- coins are script hash outputs that send funds to a multisignature address.
chooseMSCoins :: Word64    -- ^ Target price to pay.
              -> Word64    -- ^ Fee price per 1000 bytes.
              -> (Int,Int) -- ^ Multisig parameters m of n (m,n).
              -> [Coin]    -- ^ List of coins to choose from.
              -> Either String ([Coin],Word64) 
                 -- ^ Coin selection result and change amount.
chooseMSCoins target kbfee ms xs 
    | target > 0 = maybeToEither err $ greedyAdd target (getMSFee kbfee ms) xs
    | otherwise  = Left "chooseMSCoins: Target must be > 0"
    where err = "chooseMSCoins: No solution found"

-- Select coins greedily by starting from an empty solution
greedyAdd :: Word64 -> (Int -> Word64) -> [Coin] -> Maybe ([Coin],Word64)
greedyAdd target fee xs = go [] 0 [] 0 $ sortBy desc xs
    where desc a b = compare (coinValue b) (coinValue a)
          goal c = target + fee c
          go _ _ [] _ []    = Nothing
          go _ _ ps pTot [] = return (ps,pTot - (goal $ length ps))
          go acc aTot ps pTot (y:ys)
            | val + aTot >= (goal $ length acc + 1) =
                if aTot + val - target < pTot - target
                    then go [] 0 (y:acc) (aTot + val) ys
                    else return (ps,pTot - (goal $ length ps))
            | otherwise = go (y:acc) (aTot + val) ps pTot ys
            where val = coinValue y

getFee :: Word64 -> Int -> Word64
getFee kbfee count = kbfee*((len + 999) `div` 1000)
    where len = fromIntegral $ guessTxSize count [] 2 0

getMSFee :: Word64 -> (Int,Int) -> Int -> Word64
getMSFee kbfee ms count = kbfee*((len + 999) `div` 1000)
    where len = fromIntegral $ guessTxSize 0 (replicate count ms) 2 0

-- | Computes an upper bound on the size of a transaction based on some known
-- properties of the transaction.
guessTxSize :: Int         -- ^ Number of regular transaction inputs.
            -> [(Int,Int)] 
               -- ^ For every multisig input in the transaction, provide
               -- the multisig parameters m of n (m,n) for that input.
            -> Int         -- ^ Number of pay to public key hash outputs.
            -> Int         -- ^ Number of pay to script hash outputs.
            -> Int         -- ^ Upper bound on the transaction size.
guessTxSize pki msi pkout msout = 8 + inpLen + inp + outLen + out
    where inpLen = BS.length $ encode' $ 
            VarInt $ fromIntegral $ (length msi) + pki
          outLen = BS.length $ encode' $ 
            VarInt $ fromIntegral $ pkout + msout
          inp    = pki*148 + (sum $ map guessMSSize msi)
                   -- (20: hash160) + (5: opcodes) + 
                   -- (1: script len) + (8: Word64)
          out    = pkout*34 + 
                   -- (20: hash160) + (3: opcodes) + 
                   -- (1: script len) + (8: Word64)
                   msout*32

-- Size of a multisig pay2sh input
guessMSSize :: (Int,Int) -> Int
          -- OutPoint (36) + Sequence (4) + Script
guessMSSize (m,n) = 40 + (BS.length $ encode' $ VarInt $ fromIntegral scp) + scp
          -- OP_M + n*PubKey + OP_N + OP_CHECKMULTISIG
    where rdm = BS.length $ encode' $ opPushData $ BS.replicate (n*34 + 3) 0
          -- Redeem + m*sig + OP_0
          scp = rdm + m*73 + 1 

{- Build a new Tx -}

-- | Build a transaction by providing a list of outpoints as inputs
-- and a list of recipients addresses and amounts as outputs. 
buildAddrTx :: [OutPoint] -> [(String,Word64)] -> Either String Tx
buildAddrTx xs ys = buildTx xs =<< mapM f ys
    where f (s,v) = case base58ToAddr s of
            Just a@(PubKeyAddress _) -> return (PayPKHash a,v)
            Just a@(ScriptAddress _) -> return (PayScriptHash a,v)
            _ -> Left $ "buildAddrTx: Invalid address " ++ s

-- | Build a transaction by providing a list of outpoints as inputs
-- and a list of 'ScriptOutput' and amounts as outputs.
buildTx :: [OutPoint] -> [(ScriptOutput,Word64)] -> Either String Tx
buildTx xs ys = mapM fo ys >>= \os -> return $ Tx 1 (map fi xs) os 0
    where fi outPoint = TxIn outPoint BS.empty maxBound
          fo (o,v) | v <= 2100000000000000 = return $ TxOut v $ encodeOutputBS o
                   | otherwise = Left $ "buildTx: Invalid amount " ++ (show v)

-- | Data type used to specify the signing parameters of a transaction input.
-- To sign an input, the previous output script, outpoint and sighash are
-- required. When signing a pay to script hash output, an additional redeem
-- script is required.
data SigInput = SigInput 
    { sigDataOut    :: !ScriptOutput -- ^ Output script to spend. 
    , sigDataOP     :: !OutPoint     -- ^ Spending tranasction OutPoint
    , sigDataSH     :: !SigHash      -- ^ Signature type.
    , sigDataRedeem :: !(Maybe RedeemScript) -- ^ Redeem script
    } deriving (Eq, Read, Show) 

instance NFData SigInput where
    rnf (SigInput o p h b) = rnf o `seq` rnf p `seq` rnf h `seq` rnf b

instance ToJSON SigInput where
    toJSON (SigInput so op sh rdm) = object $
        [ "pkscript" .= so
        , "outpoint" .= op
        , "sighash"  .= sh
        ] ++ if isNothing rdm then [] else [ "redeem" .= fromJust rdm ]

instance FromJSON SigInput where
    parseJSON (Object o) = do
        so  <- o .: "pkscript"
        op  <- o .: "outpoint"
        sh  <- o .: "sighash"
        rdm <- o .:? "redeem"
        return $ SigInput so op sh rdm
    parseJSON _ = mzero

-- | Sign a transaction by providing the 'SigInput' signing parameters and a
-- list of private keys. The signature is computed within the 'SecretT' monad
-- to generate the random signing nonce. This function returns a transaction
-- completion status. If false, some of the inputs are not fully signed or are
-- non-standard. 
signTx :: Monad m 
       => Tx                        -- ^ Transaction to sign
       -> [SigInput]                -- ^ SigInput signing parameters
       -> [PrvKey]                  -- ^ List of private keys to use for signing
       -> EitherT String (SecretT m) (Tx, Bool) 
          -- ^ (Signed transaction, Status)
signTx otx@(Tx _ ti _ _) sigis allKeys 
    | null ti   = left "signTx: Transaction has no inputs"
    | otherwise = do
        tx <- foldM go otx $ findSigInput sigis ti
        return (tx, verifyStdTx tx sigDat)
  where 
    sigDat = map (\(SigInput so op _ _) -> (so, op)) sigis
    go tx (sigi@(SigInput so _ _ rdmM), i) = do
        keys <- liftEither $ sigKeys so rdmM allKeys
        if null keys
            then return tx
            else foldM (\t k -> fst <$> signInput t i sigi k) tx keys

-- | Sign a single input in a transaction within the 'SecretT' monad. This 
-- function will return a completion status only for that input. If false, 
-- that input is either non-standard or not fully signed.
signInput :: Monad m => Tx -> Int -> SigInput -> PrvKey 
          -> EitherT String (SecretT m) (Tx, Bool)
signInput tx i (SigInput so _ sh rdmM) key = do
    sig <- flip TxSignature sh <$> lift (signMsg msg key)
    si  <- liftEither $ buildInput tx i so rdmM sig $ derivePubKey key
    let newTx = tx{ txIn = updateIndex i (txIn tx) (f si) }
    return (newTx, verifyStdInput newTx i so)
  where
    f si x = x{ scriptInput = encodeInputBS si }
    msg | isJust rdmM = txSigHash tx (encodeOutput $ fromJust rdmM) i sh
        | otherwise   = txSigHash tx (encodeOutput so) i sh

-- | Sign a transaction by providing the 'SigInput' signing paramters and 
-- a list of private keys. The signature is computed deterministically as
-- defined in RFC-6979. This function returns a transaction completion status.
-- If false, some of the inputs are not fully signed or are non-standard.
detSignTx :: Tx              -- ^ Transaction to sign
          -> [SigInput]      -- ^ SigInput signing parameters
          -> [PrvKey]        -- ^ List of private keys to use for signing
          -> Either String (Tx, Bool) 
            -- ^ (Signed transaction, Status)
detSignTx otx@(Tx _ ti _ _) sigis allKeys
    | null ti   = Left "signTx: Transaction has no inputs"
    | otherwise = do
        tx <- foldM go otx $ findSigInput sigis ti
        return (tx, verifyStdTx tx sigDat)
  where 
    sigDat = map (\(SigInput so op _ _) -> (so, op)) sigis
    go tx (sigi@(SigInput so _ _ rdmM), i) = do
        keys <- sigKeys so rdmM allKeys
        if null keys
            then return tx
            else foldM (\t k -> fst <$> detSignInput t i sigi k) tx keys

-- | Sign a single input in a transaction deterministically (RFC-6979). This
-- function will return a completion status only for that input. If false, 
-- that input is either non-standard or not fully signed.
detSignInput :: Tx -> Int -> SigInput -> PrvKey -> Either String (Tx, Bool)
detSignInput tx i (SigInput so _ sh rdmM) key = do
    let sig = TxSignature (detSignMsg msg key) sh
    si <- buildInput tx i so rdmM sig $ derivePubKey key
    let newTx = tx{ txIn = updateIndex i (txIn tx) (f si) }
    return (newTx, verifyStdInput newTx i so)
  where
    f si x = x{ scriptInput = encodeInputBS si }
    msg | isJust rdmM = txSigHash tx (encodeOutput $ fromJust rdmM) i sh
        | otherwise   = txSigHash tx (encodeOutput so) i sh

-- Order the SigInput with respect to the transaction inputs. This allow the
-- users to provide the SigInput in any order. Users can also provide only a
-- partial set of SigInputs.
findSigInput :: [SigInput] -> [TxIn] -> [(SigInput, Int)]
findSigInput si ti = 
    catMaybes $ map g $ zip (matchTemplate si ti f) [0..]
  where 
    f s txin = sigDataOP s == prevOutput txin
    g (Just s, i)  = Just (s,i)
    g (Nothing, _) = Nothing

-- Find from the list of private keys which one is required to sign the 
-- provided ScriptOutput. 
sigKeys :: ScriptOutput -> (Maybe RedeemScript) -> [PrvKey] 
        -> Either String [PrvKey]
sigKeys so rdmM keys = do
    case (so, rdmM) of
        (PayPK p, Nothing) -> return $ 
            map fst $ maybeToList $ find ((== p) . snd) zipKeys
        (PayPKHash a, Nothing) -> return $ 
            map fst $ maybeToList $ find ((== a) . pubKeyAddr . snd) zipKeys
        (PayMulSig ps r, Nothing) -> return $ 
            map fst $ take r $ filter ((`elem` ps) . snd) zipKeys
        (PayScriptHash _, Just rdm) ->
            sigKeys rdm Nothing keys
        _ -> Left "sigKeys: Could not decode output script" 
  where
    zipKeys = zip keys (map derivePubKey keys)

-- Construct an input, given a signature and a public key
buildInput :: Tx -> Int -> ScriptOutput -> (Maybe RedeemScript) 
           -> TxSignature -> PubKey -> Either String ScriptInput
buildInput tx i so rdmM sig pub = case (so, rdmM) of
    (PayPK _, Nothing) -> 
        return $ RegularInput $ SpendPK sig
    (PayPKHash _, Nothing) -> 
        return $ RegularInput $ SpendPKHash sig pub
    (PayMulSig msPubs r, Nothing) -> do
        let mSigs = take r $ catMaybes $ matchTemplate allSigs msPubs f
        return $ RegularInput $ SpendMulSig mSigs
    (PayScriptHash _, Just rdm) -> do
        inp  <- buildInput tx i rdm Nothing sig pub
        return $ ScriptHashInput (getRegularInput inp) rdm
    _ -> Left "buildInput: Invalid output/redeem script combination"
  where 
    scp     = scriptInput $ txIn tx !! i
    allSigs = nub $ sig : case decodeInputBS scp of
        Right (ScriptHashInput (SpendMulSig xs) _) -> xs
        Right (RegularInput    (SpendMulSig xs))   -> xs
        _ -> []
    out = encodeOutput so
    f (TxSignature x sh) p = verifySig (txSigHash tx out i sh) x p

{- Tx verification -}

-- | Verify if a transaction is valid and all of its inputs are standard.
verifyStdTx :: Tx -> [(ScriptOutput, OutPoint)] -> Bool
verifyStdTx tx xs = 
    all go $ zip (matchTemplate xs (txIn tx) f) [0..]
  where
    f (_,o) txin        = o == prevOutput txin
    go (Just (so,_), i) = verifyStdInput tx i so
    go _                = False

-- | Verify if a transaction input is valid and standard.
verifyStdInput :: Tx -> Int -> ScriptOutput -> Bool
verifyStdInput tx i so' = 
    go (scriptInput $ txIn tx !! i) so'
  where
    go inp so = case decodeInputBS inp of
        Right (RegularInput (SpendPK (TxSignature sig sh))) -> 
            let pub = getOutputPubKey so
            in  verifySig (txSigHash tx out i sh) sig pub
        Right (RegularInput (SpendPKHash (TxSignature sig sh) pub)) ->
            let a = getOutputAddress so
            in pubKeyAddr pub == a && 
                verifySig (txSigHash tx out i sh) sig pub
        Right (RegularInput (SpendMulSig sigs)) ->
            let pubs = getOutputMulSigKeys so
                r    = getOutputMulSigRequired so
            in  countMulSig tx out i pubs sigs == r
        Right (ScriptHashInput si rdm) ->
            scriptAddr rdm == getOutputAddress so && 
            go (encodeInputBS $ RegularInput si) rdm
        _ -> False
      where
        out = encodeOutput so
                      
-- Count the number of valid signatures
countMulSig :: Tx -> Script -> Int -> [PubKey] -> [TxSignature] -> Int
countMulSig _ _ _ [] _  = 0
countMulSig _ _ _ _  [] = 0
countMulSig tx out i (pub:pubs) sigs@(TxSignature sig sh:rest)
    | verifySig (txSigHash tx out i sh) sig pub = 
         1 + countMulSig tx out i pubs rest
    | otherwise = countMulSig tx out i pubs sigs

