module Hasql.Postgres.LibPQ.Result where

import Hasql.Postgres.Prelude hiding (Error)
import qualified Database.PostgreSQL.LibPQ as L
import qualified ListT


-- |
-- Either a failure with no result but some description or a comprehensive one.
data Error =
  NoResult 
    (Maybe ByteString) |
  -- | Status, state, message, detail, hint.
  ResultError 
    ResultErrorStatus ByteString (Maybe ByteString) (Maybe ByteString) (Maybe ByteString)
  deriving (Show, Typeable)
  

data ResultErrorStatus =
  BadResponse | NonfatalError | FatalError
  deriving (Show, Typeable, Eq, Ord, Enum, Bounded)


data Success =
  CommandOK !(Maybe ByteString) |
  Stream !Stream


parse :: L.Connection -> Maybe L.Result -> IO (Either Error Success)
parse c =
  \case
    Nothing ->
      Left . NoResult <$> L.errorMessage c
    Just r ->
      L.resultStatus r >>=
        \case
          L.CommandOk ->
            Right . CommandOK <$> L.cmdTuples r
          L.TuplesOk ->
            Right . Stream <$> stream r
          L.BadResponse ->
            Left <$> statusError BadResponse
          L.NonfatalError ->
            Left <$> statusError NonfatalError
          L.FatalError ->
            Left <$> statusError FatalError
          r ->
            $bug $ "Unsupported result status: " <> show r
      where
        statusError s =
          ResultError s <$> state <*> message <*> detail <*> hint
          where
            state   = fromJust <$> L.resultErrorField r L.DiagSqlstate
            message = L.resultErrorField r L.DiagMessagePrimary
            detail  = L.resultErrorField r L.DiagMessageDetail
            hint    = L.resultErrorField r L.DiagMessageHint

-- |
-- A width of a row and a stream of cells.
type Stream =
  (Int, ListT IO (Maybe ByteString))


stream :: L.Result -> IO Stream
stream r =
  do
    rows <- L.ntuples r
    cols <- L.nfields r
    let
      rowsLoop ri =
        if ri < rows
          then colsLoop 0
          else mzero
        where
          colsLoop ci =
            if ci < cols
              then do
                v <- lift (L.getvalue r ri ci)
                ListT.cons v (colsLoop (succ ci))
              else rowsLoop (succ ri)
    return (colToInt cols, rowsLoop 0)
  where
    colToInt (L.Col n) = fromIntegral n
