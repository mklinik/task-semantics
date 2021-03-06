module Data.Task.Input
  ( Path(..), Action(..), Dummy(..), Input(..)
  , dummyfy, reify, strip, fill
  , usage, parse
  ) where


import Preload

import Test.QuickCheck (Gen, vectorOf)

import Data.Task.Internal



-- Paths -----------------------------------------------------------------------


data Path
  = GoLeft
  | GoRight
  deriving (Eq, Show)


instance Pretty Path where
  pretty GoLeft  = "l"
  pretty GoRight = "r"


parsePath :: Text -> Either Msg Path
parsePath "l"   = ok $ GoLeft
parsePath "r"   = ok $ GoRight
parsePath other = throw $ "!! " <> quote other <> " is not a valid path, type `help` for more info"



-- Inputs ----------------------------------------------------------------------

-- Real actions --


data Action :: Type where
  Change       :: Basic b => b -> Action
  Empty        :: Action
  Pick         :: Path -> Action
  Continue     :: Action
  -- PickWith     :: Label -> Action
  -- ContinueWith :: Label -> Action


instance Eq Action where
  Change x == Change y
    | Just Refl <- sameT x y = x == y
    | otherwise              = False
  Empty    == Empty          = True
  Pick x   == Pick y         = x == y
  Continue == Continue       = True
  _        == _              = False


instance Pretty Action where
  pretty (Change x) = "change " <> show x
  pretty (Empty)    = "empty"
  pretty (Pick p)   = "pick" <> pretty p
  pretty (Continue) = "cont"


instance Show Action where
  showsPrec d (Change x) =
    showParen (d > p) (showString "Change " <<
    showParen (d > pred p) (showsPrec p x << showString " :: " << showsPrec p (typeOf x)))
      where p = 10
  showsPrec d (Empty) =
    showParen (d > p) $ showString "Empty"
      where p = 10
  showsPrec d (Pick x) =
    showParen (d > p) $ showString "Pick " << showsPrec (succ p) x
      where p = 10
  showsPrec d (Continue) =
    showParen (d > p) $ showString "Continue"
      where p = 10



-- Dummy actions --


data Dummy :: Type where
  AChange       :: Basic b => Proxy b -> Dummy
  AEmpty        :: Dummy
  APick         :: Path -> Dummy
  AContinue     :: Dummy
  -- APickWith     :: Label -> Dummy
  -- AContinueWith :: Label -> Dummy


instance Eq Dummy where
  AChange x == AChange y
    -- We're comparing proxies, they are always equal when the types are equal.
    | Just Refl <- sameT x y = True
    | otherwise              = False
  AEmpty    == AEmpty        = True
  APick x   == APick y       = x == y
  AContinue == AContinue     = True
  _         == _             = False


instance Pretty Dummy where
  pretty (AChange _) = "change <val>"
  pretty (AEmpty)    = "empty"
  pretty (APick p)   = "pick" <> pretty p
  pretty (AContinue) = "cont"


instance Show Dummy where
  showsPrec d (AChange x) =
    showParen (d > p) $ showString "AChange " << showsPrec (succ p) x
      where p = 10
  showsPrec d (AEmpty) =
    showParen (d > p) $ showString "AEmpty"
      where p = 10
  showsPrec d (APick x) =
    showParen (d > p) $ showString "APick " << showsPrec (succ p) x
      where p = 10
  showsPrec d (AContinue) =
    showParen (d > p) $ showString "AContinue"
      where p = 10



-- Inputs --


data Input a
  = ToFirst (Input a)
  | ToHere a
  | ToSecond (Input a)
  deriving (Eq, Show, Functor, Foldable, Traversable)


instance Pretty a => Pretty (Input a) where
  pretty (ToFirst e)  = "l " <> pretty e
  pretty (ToHere a)  = pretty a
  pretty (ToSecond e) = "r " <> pretty e



-- Conformance -----------------------------------------------------------------


dummyfy :: Action -> Dummy
dummyfy (Change x) = AChange (proxyOf x)
dummyfy (Empty)    = AEmpty
dummyfy (Pick p)   = APick p
dummyfy (Continue) = AContinue


reify :: Dummy -> Gen (List Action)
reify (AChange p) = map Change <$> vectorOf 5 (arbitraryOf p)
reify (AEmpty)    = pure [ Empty ]
reify (APick p)   = pure [ Pick p ]
reify (AContinue) = pure [ Continue ]


strip :: Input Action -> Input Dummy
strip = map dummyfy

fill :: Input Dummy -> Gen (List (Input Action))
fill = map sequence << sequence << map reify



-- Parsing ---------------------------------------------------------------------


usage :: Text
usage = unlines
  [ ":: Possible events are:"
  , "    change <value> : change current editor to <value> "
  , "    empty          : empty current editor"
  , "    pick <path>    : pick amongst the possible options"
  , "    pick <label>   : pick the option labeld with <label>"
  , "    cont           : continue with the next task"
  , "    cont <label>   : continue with the task labeld <label>"
  , "    l <event>      : send <event> to the left task"
  , "    r <event>      : send <event> to the right task"
  , "    help           : show this message"
  , ""
  , "where values can be:"
  , "    ()          : Unit"
  , "    True, False : Booleans"
  , "    1, 32, -42  : Integers"
  , "    \"Hello\"   : Strings"
  , ""
  , "paths are of the form:"
  , "   l <path>? : go left"
  , "   r <path>? : go right"
  , ""
  , "and labels always start with a Capital letter"
  ]

parse :: List Text -> Either Msg (Input Action)
parse [ "change", val ]
  | Just v <- read val :: Maybe Unit   = ok $ ToHere $ Change v
  | Just v <- read val :: Maybe Bool   = ok $ ToHere $ Change v
  | Just v <- read val :: Maybe Int    = ok $ ToHere $ Change v
  | Just v <- read val :: Maybe Text   = ok $ ToHere $ Change v
  | Just v <- read val :: Maybe [Bool] = ok $ ToHere $ Change v
  | Just v <- read val :: Maybe [Int]  = ok $ ToHere $ Change v
  | Just v <- read val :: Maybe [Text] = ok $ ToHere $ Change v
  | otherwise                          = throw $ "!! Error parsing value " <> quote val
parse [ "pick", next ]                 = map (ToHere << Pick) $ parsePath next
parse [ "cont" ]                       = ok $ ToHere $ Continue
parse ("f" : rest)                     = map ToFirst $ parse rest
parse ("s" : rest)                     = map ToSecond $ parse rest
parse [ "help" ]                       = throw usage
parse other                            = throw $ "!! " <> quote (unwords other) <> " is not a valid command, type `help` for more info"
