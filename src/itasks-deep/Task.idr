module Task


-- Types -----------------------------------------------------------------------

ID : Type
ID = Int

UI : Type
UI = String

State : Type
State = Int


-- Values --

data Value : Type -> Type where
  NoValue : Value a
  JustValue : a -> Value a


-- Events --

data Event : Type -> Type where
  Change : ID -> Value a -> Event a
  Commit : ID -> Event a
  Continue : ID -> Event a


-- Tasks --

data Task : Type -> Type where
  -- Lifting
  Pure : a -> Task a
  -- Primitive combinators
  Seq : ID -> Task a -> (a -> Task b) -> Task b
  Par : ID -> Task a -> Task b -> Task ( a, b )
  -- User interaction
  Edit : ID -> Value a -> Task a
  -- Share interaction
  Get : ID -> Task State
  Put : ID -> State -> Task ()

pure : a -> Task a
pure x =
  Pure x

unit : Task ()
unit =
  pure ()


-- Semantics -------------------------------------------------------------------

ui : Task a -> UI
ui t =
  ?ui

normalise : Task a -> State -> ( Task a, State )
normalise task state =
  case task of
    -- Combinators
    Seq id left func =>
      let
        ( newLeft, newState ) = Task.normalise left state
      in
      case newLeft of
        Pure a =>
          ( func a, newState )
        _ =>
          ( Seq id newLeft func, newState )
    Par id left right =>
      let
        ( newLeft, newState ) = Task.normalise left state
        ( newRight, newerState ) = Task.normalise right newState
      in
      case ( newLeft, newRight ) of
        ( Pure a, Pure b ) =>
          ( Pure ( a, b ), newerState )
        ( newLeft, newRight ) =>
          ( Par id newLeft newRight, newerState )
    -- State
    Get id =>
      ( pure state, state )

    Put id newState =>
      ( unit, newState )
    -- Pure and Edit are values
    _ =>
      ( task, state )

value : Task a -> State -> ( Value a, State )
value task state =
  let
    ( newTask, newState ) = normalise task state
  in
  case newTask of
    Pure val =>
      ( JustValue val, newState )
    Edit id val =>
      ( val, newState )
    _ =>
      ( NoValue, newState )

step : Task a -> State -> Event b -> ( Task a, State )
step state event task =
  ?step