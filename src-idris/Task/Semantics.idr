module Task


import public Control.Monad.Trace

import Task.Internal

import Helpers


%default total
%access export

%hide Language.Reflection.Elab.Tactics.normalise



-- Errors ----------------------------------------------------------------------


data NotApplicable
  = CouldNotChange
  | CouldNotFind Label
  | CouldNotContinue
  | CouldNotHandle Input


Show NotApplicable where
  show (CouldNotChange)   = "Could not change value because types do not match"
  show (CouldNotFind l)   = "Could not find label `" ++ l ++ "`"
  show (CouldNotContinue) = "Could not continue because there is no value to continue with"
  show (CouldNotHandle i) = "Could not handle input `" ++ show i ++ "`"



-- Observations ----------------------------------------------------------------


ui : MonadRef l m => TaskT m a -> m String
ui (Edit {r} (Just x))   with ( show r )
  | show_r               = pure $ "□(" ++ show x ++ ")"
ui (Edit Nothing)        = pure $ "□(_)"
ui (Store {r} loc)       with ( show r )
  | show_r               = pure $ "■(" ++ show !(deref loc) ++ ")"
ui (And left rght)       = pure $ !(ui left) ++ "   ⋈   " ++ !(ui rght)
ui (Or left rght)        = pure $ !(ui left) ++ "   ◆   " ++ !(ui rght)
ui (Xor left rght) with ( delabel left, delabel rght )
  | ( Xor _ _, Xor _ _ ) = pure $                 !(ui left) ++ " ◇ " ++ !(ui rght)
  | ( Xor _ _, _       ) = pure $                 !(ui left) ++ " ◇ " ++ fromMaybe "…" (label rght)
  | ( _,       Xor _ _ ) = pure $ fromMaybe "…" (label left) ++ " ◇ " ++ !(ui rght)
  | ( _,       _       ) = pure $ fromMaybe "…" (label left) ++ " ◇ " ++ fromMaybe "…" (label rght)
ui (Fail)                = pure $ "↯"
ui (Then this cont)      = pure $ !(ui this) ++ " ▶…"
ui (Next this cont)      = pure $ !(ui this) ++ " ▷…"
ui (Label l this)        = pure $ l ++ ":\n\t" ++ !(ui this)
ui (Lift _)              = pure $ "<lift>"


value : MonadRef l m => TaskT m a -> m (Maybe (typeOf a))
value (Edit val)      = pure $ val
value (Store loc)     = pure $ Just !(deref loc)
value (And left rght) = pure $ !(value left) <&> !(value rght)
value (Or left rght)  = pure $ !(value left) <|> !(value rght)
value (Xor _ _)       = pure $ Nothing
value (Fail)          = pure $ Nothing
value (Then _ _)      = pure $ Nothing
value (Next _ _)      = pure $ Nothing
value (Label _ this)  = value this
value (Lift _)        = pure $ Nothing


choices : TaskT m a -> List Path
choices (Xor left rght) =
  --XXX: No with-block possible?
  case ( delabel left, delabel rght ) of
    ( Fail, Fail ) => []
    ( left, Fail ) => map GoLeft (GoHere :: choices left)
    ( Fail, rght ) => map GoRight (GoHere :: choices rght)
    ( left, rght ) => map GoLeft (GoHere :: choices left) ++ map GoRight (GoHere :: choices rght)
choices _          = []


inputs : MonadRef l m => TaskT m a -> m (List Input)
inputs (Edit {r} _)     = pure $ [ ToHere (Change {c=r} Anything), ToHere Empty ]
inputs (Store {r} _)    = pure $ [ ToHere (Change {c=r} Anything) ]
inputs (And left rght)  = pure $ map ToLeft !(inputs left) ++ map ToRight !(inputs rght)
inputs (Or left rght)   = pure $ map ToLeft !(inputs left) ++ map ToRight !(inputs rght)
inputs this@(Xor _ _)   = pure $ map (ToHere . PickWith) (labels this) ++ map (ToHere . Pick) (choices this)
inputs (Fail)           = pure $ []
inputs (Then this _)    = inputs this
inputs (Next this next) = do
    always <- inputs this
    Just v <- value this | Nothing => pure always
    pure $ map ToHere (go (next v)) ++ always
  where
    go : TaskT m a -> List Action
    go task with (delabel task)
      | Xor _ _ = map ContinueWith $ labels task
      | Fail    = []
      | _       = [ Continue ]
inputs (Label _ this)   = inputs this
inputs (Lift _)         = pure $ []



-- Predicates ------------------------------------------------------------------


failing : TaskT m a -> Bool
failing (Edit _)        = False
failing (Store _)       = False
failing (And left rght) = failing left && failing rght
failing (Or left rght)  = failing left && failing rght
failing (Xor left rght) = failing left && failing rght
failing (Fail)          = True
failing (Then this _)   = failing this
failing (Next this _)   = failing this
failing (Label _ this)  = failing this
failing (Lift _)        = False --FIXME: needs normalisation!!!



-- Normalisation ---------------------------------------------------------------


normalise : MonadRef l m => TaskT m a -> m (TaskT m a)

-- Step --
normalise (Then this cont) = do
  this_new <- normalise this
  case !(value this_new) of
    Nothing => pure $ Then this_new cont
    Just v  =>
      --FIXME: should we use normalise here instead of just eval?
      let next = cont v in
      if failing next then
        pure $ Then this_new cont
      else
        normalise next

-- Evaluate --
normalise (And left rght) = do
  left_new <- normalise left
  rght_new <- normalise rght
  pure $ And left_new rght_new

normalise (Or left rght) = do
  left_new <- normalise left
  case !(value left_new) of
    Just _  => pure $ left_new
    Nothing => do
      rght_new <- normalise rght
      case !(value rght_new) of
        Just _  => pure $ rght_new
        Nothing => pure $ Or left_new rght_new

normalise (Next this cont) = do
  this_new <- normalise this
  pure $ Next this_new cont

-- Label --
normalise (Label l this) with (keeper this)
  | False = normalise this
  | True  = do
      this_new <- normalise this
      pure $ Label l this_new

-- Lift --
normalise (Lift a) = do
  x <- a
  pure $ Edit (Just x)

-- Values --
normalise task = do
  pure $ task


initialise : MonadRef l m => TaskT m a -> m (TaskT m a)
initialise = normalise



-- Input handling --------------------------------------------------------------


covering
handle : MonadTrace NotApplicable m => MonadRef l m => TaskT m a -> Input -> m (TaskT m a)

-- Edit --
handle (Edit _) (ToHere Empty) =
  pure $ Edit Nothing

handle (Edit {r} val) (ToHere (Change {c} val_new)) with (decEq c r)
  handle (Edit _)   (ToHere (Change val_new))       | Yes Refl = pure $ Edit $ toMaybe val_new
  handle (Edit val) (ToHere (Change _))             | No _     = trace CouldNotChange $ Edit val

handle (Store {r} loc) (ToHere (Change {c} val_new)) with (decEq c r)
  handle (Store loc) (ToHere (Change (Exactly val_new))) | Yes Refl = do
    loc := val_new
    pure $ Store loc
  handle (Store loc) (ToHere (Change (Anything)))        | Yes Refl = trace CouldNotChange $ Store loc
  handle (Store loc) (ToHere (Change _))                 | No _     = trace CouldNotChange $ Store loc

-- Pass to left or rght --
handle (And left rght) (ToLeft input) = do
  -- Pass the input to left
  left_new <- handle left input
  pure $ And left_new rght

handle (And left rght) (ToRight input) = do
  -- Pass the input to rght
  rght_new <- handle rght input
  pure $ And left rght_new

handle (Or left rght) (ToLeft input) = do
  -- Pass the input to left
  left_new <- handle left input
  pure $ Or left_new rght

handle (Or left rght) (ToRight input) = do
  -- Pass the input to rght
  rght_new <- handle rght input
  pure $ Or left rght_new

-- Interact --
handle task@(Xor left _) (ToHere (Pick (GoLeft p))) =
  -- Go left
  --FIXME: add failing for left?
  handle (assert_smaller task (delabel left)) (ToHere (Pick p))

handle task@(Xor _ rght) (ToHere (Pick (GoRight p))) =
  -- Go rght
  --FIXME: add failing for rght?
  handle (assert_smaller task (delabel rght)) (ToHere (Pick p))

handle task (ToHere (Pick GoHere)) =
  -- Go here
  pure $ task

handle task@(Xor _ _) (ToHere (PickWith l)) =
  case find l task of
    Nothing => trace (CouldNotFind l) task
    --XXX: needs `assert_smaller` for totallity, be aware of long type checks...
    -- Just p  => handle task (assert_smaller (ToHere (PickWith l)) (ToHere (Pick p)))
    Just p  => handle task (ToHere (Pick p))

handle task@(Next this cont) (ToHere Continue) =
  -- When pressed continue rewrite to an internal step
  pure $ Then this cont

handle task@(Next this cont) (ToHere (ContinueWith l)) =
  case !(value this) of
    Nothing => trace CouldNotContinue task
    Just v  =>
      let
        next = cont v
      in
      case find l next of
        Nothing => trace (CouldNotFind l) task
        Just p  => handle next (ToHere (Pick p))

-- Pass to this --
handle (Then this cont) input = do
  -- Pass the input to this
  this_new <- handle this input
  pure $ Then this_new cont

handle (Next this cont) input = do
  -- Pass the input to this
  this_new <- handle this input
  pure $ Next this_new cont

-- Label --
handle (Label l this) input with (keeper this)
  | False = handle this input
  | True = do
      this_new <- handle this input
      pure $ Label l this_new

-- Rest --
handle task input =
  -- Case `Fail`: Evaluation continues indefinitely
  trace (CouldNotHandle input) task


covering
drive : MonadTrace NotApplicable m => MonadRef l m => TaskT m a -> Input -> m (TaskT m a)
drive task input =
  handle task input >>= normalise
