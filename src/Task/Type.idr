module Task.Type

%default total
%access public export


-- Type universe ---------------------------------------------------------------

data BasicTy
    = IntTy
    | StringTy

data Ty
    = UnitTy
    | PairTy Ty Ty
    | Basic BasicTy

typeOfBasic : BasicTy -> Type
typeOfBasic IntTy    = Int
typeOfBasic StringTy = String

||| Conversion of Task types to Idris types.
typeOf : Ty -> Type
typeOf UnitTy       = ()
typeOf (PairTy x y) = ( typeOf x, typeOf y )
typeOf (Basic b)    = typeOfBasic b

-- Lemmas ----------------------------------------------------------------------

Uninhabited (UnitTy = PairTy x y) where
    uninhabited Refl impossible

Uninhabited (UnitTy = Basic b) where
    uninhabited Refl impossible

Uninhabited (PairTy x y = Basic b) where
    uninhabited Refl impossible

Uninhabited (IntTy = StringTy) where
    uninhabited Refl impossible

-- basic_neq : (contra : (a = b) -> Void) -> Dec (Basic a = Basic b)

basic_neq : (a = b -> Void) -> (Basic a = Basic b) -> Void
basic_neq contra Refl = contra Refl

snd_neq : (y = y' -> Void) -> (PairTy x y = PairTy x y') -> Void
snd_neq contra Refl = contra Refl

fst_neq : (x = x' -> Void) -> (PairTy x y = PairTy x' y) -> Void
fst_neq contra Refl = contra Refl

both_neq : (x = x' -> Void) -> (y = y' -> Void) -> (PairTy x y = PairTy x' y') -> Void
both_neq contra_x contra_y Refl = contra_x Refl


-- Decidablility ---------------------------------------------------------------

DecEq BasicTy where
    decEq IntTy    IntTy    = Yes Refl
    decEq StringTy StringTy = Yes Refl
    decEq IntTy    StringTy = No absurd
    decEq StringTy IntTy    = No (negEqSym absurd)

DecEq Ty where
    decEq UnitTy       UnitTy                                             = Yes Refl
    decEq (PairTy x y) (PairTy x' y')     with (decEq x x')
      decEq (PairTy x y) (PairTy x y')    | (Yes Refl)  with (decEq y y')
        decEq (PairTy x y) (PairTy x y)   | (Yes Refl)  | (Yes Refl)      = Yes Refl
        decEq (PairTy x y) (PairTy x y')  | (Yes Refl)  | (No contra)     = No (snd_neq contra)
      decEq (PairTy x y) (PairTy x' y')   | (No contra) with (decEq y y')
        decEq (PairTy x y) (PairTy x' y)  | (No contra) | (Yes Refl)      = No (fst_neq contra)
        decEq (PairTy x y) (PairTy x' y') | (No contra) | (No contra')    = No (both_neq contra contra')
    decEq (Basic a)  (Basic b)   with (decEq a b)
      decEq (Basic b)  (Basic b) | (Yes Refl)                             = Yes Refl
      decEq (Basic a)  (Basic b) | (No contra)                            = No (basic_neq contra)
    decEq UnitTy       (PairTy x y)                                       = No absurd
    decEq (PairTy x y) UnitTy                                             = No (negEqSym absurd)
    decEq UnitTy       (Basic b)                                          = No absurd
    decEq (Basic b)    UnitTy                                             = No (negEqSym absurd)
    decEq (PairTy x y) (Basic b)                                          = No absurd
    decEq (Basic b)    (PairTy x y)                                       = No (negEqSym absurd)
