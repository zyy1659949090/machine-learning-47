{-# LANGUAGE GeneralizedNewtypeDeriving #-}
{-# LANGUAGE DeriveTraversable #-}
{-# LANGUAGE DeriveFoldable #-}
{-# LANGUAGE DeriveFunctor #-}
{-# LANGUAGE TypeFamilies #-}
{-# LANGUAGE KindSignatures #-}
{- |
Module      :  Data.ML.Model
Description :  Model class.
Copyright   :  (c) Paweł Nowak
License     :  MIT

Maintainer  :  pawel834@gmail.com
Stability   :  experimental

-}
module Data.ML.Model where

import Control.Applicative
import Data.Bytes.Serial
import Data.Foldable
import Data.Monoid
import Data.Traversable
import Linear

-- | A machine learning model.
class (Traversable m, Additive m, Serial1 m) => Model m where
    type Input m :: * -> *
    type Output m :: * -> *
    predict :: Floating a => Input m a -> m a -> Output m a

-- | A model that passes through its input.
newtype IdentityModel (f :: * -> *) (a :: *) = IdentityModel (V0 a)
     deriving (Functor, Applicative, Monad, Foldable, Traversable, Additive)

instance Serial1 (IdentityModel f) where
    serializeWith _ _ = return ()
    deserializeWith _ = return (IdentityModel V0)

instance Model (IdentityModel f) where
    type Input (IdentityModel f) = f
    type Output (IdentityModel f) = f
    predict x _ = x

-- | A composition of models.
data CompositeModel f g a = CompositeModel (f a) (g a)

instance (Functor f, Functor g) => Functor (CompositeModel f g) where
    fmap h (CompositeModel f g) = CompositeModel (fmap h f) (fmap h g)

instance (Additive f, Additive g) => Additive (CompositeModel f g) where
    zero = CompositeModel zero zero
    CompositeModel f g ^+^ CompositeModel f' g' =
        CompositeModel (f ^+^ f') (g ^+^ g')
    CompositeModel f g ^-^ CompositeModel f' g' =
        CompositeModel (f ^-^ f') (g ^-^ g')
    lerp alpha (CompositeModel f g) (CompositeModel f' g') =
        CompositeModel (lerp alpha f f') (lerp alpha g g')
    liftU2 h (CompositeModel f g) (CompositeModel f' g') =
        CompositeModel (liftU2 h f f') (liftU2 h g g')
    liftI2 h (CompositeModel f g) (CompositeModel f' g') =
        CompositeModel (liftI2 h f f') (liftI2 h g g')

instance (Foldable f, Foldable g) => Foldable (CompositeModel f g) where
    foldMap h (CompositeModel f g) = foldMap h f <> foldMap h g

instance (Traversable f, Traversable g) => Traversable (CompositeModel f g) where
    traverse h (CompositeModel f g) = CompositeModel
        <$> traverse h f
        <*> traverse h g

instance (Serial1 f, Serial1 g) => Serial1 (CompositeModel f g) where
    serializeWith h (CompositeModel f g) =
        serializeWith h f *>
        serializeWith h g
    deserializeWith h = CompositeModel
        <$> deserializeWith h
        <*> deserializeWith h

instance (Model f, Model g, Output f ~ Input g) => Model (CompositeModel f g) where
    type Input (CompositeModel f g) = Input f
    type Output (CompositeModel f g) = Output g
    predict x (CompositeModel f g) = predict (predict x f) g

-- | Chains two models.
(|>) :: Model f => Model g => Output f ~ Input g
     => f a -> g a -> CompositeModel f g a
(|>) = CompositeModel