-- Module for connecting to the AUR servers,
-- downloading PKGBUILDs and source tarballs, and handling them.

{-

Copyright 2012, 2013, 2014 Colin Woodbury <colingw@gmail.com>

This file is part of Aura.

Aura is free software: you can redistribute it and/or modify
it under the terms of the GNU General Public License as published by
the Free Software Foundation, either version 3 of the License, or
(at your option) any later version.

Aura is distributed in the hope that it will be useful,
but WITHOUT ANY WARRANTY; without even the implied warranty of
MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
GNU General Public License for more details.

You should have received a copy of the GNU General Public License
along with Aura.  If not, see <http://www.gnu.org/licenses/>.

-}

module Aura.Packages.AUR
    ( aurLookup
    , aurRepo
    , isAurPackage
    , sourceTarball
    , aurInfo
    , aurSearch
    , pkgUrl
    ) where

import           Control.Applicative
import           Data.List            (sortBy)
import           Data.Maybe
import qualified Data.Text            as T
import qualified Data.Traversable     as Traversable (mapM)
import           Linux.Arch.Aur
import           System.FilePath      ((</>))

import           Aura.Monad.Aura
import           Aura.Pkgbuild.Base
import           Aura.Settings.Base
import           Aura.Core

import           Utilities            (decompress)
import           Internet

---

aurLookup :: String -> Aura (Maybe Buildable)
aurLookup name = fmap (makeBuildable name . T.unpack) <$> pkgbuild name

aurRepo :: Repository
aurRepo = Repository $ \name ->
    aurLookup name >>= Traversable.mapM packageBuildable

makeBuildable :: String -> Pkgbuild -> Buildable
makeBuildable name pb = Buildable
    { baseNameOf   = name
    , pkgbuildOf   = pb
    , isExplicit   = False
    , buildScripts = f }
    where f fp = sourceTarball fp name >>= Traversable.mapM decompress

isAurPackage :: String -> Aura Bool
isAurPackage name = isJust <$> pkgbuild name

----------------
-- AUR PKGBUILDS
----------------
-- These are redundant!
aurLink :: String
aurLink = "https://aur.archlinux.org/packages/"

pkgUrl :: String -> String
pkgUrl pkg = aurLink </> take 2 pkg </> pkg

------------------
-- SOURCE TARBALLS
------------------
tarballUrl :: String -> String
tarballUrl pkg = pkgUrl pkg </> pkg ++ ".tar.gz"

sourceTarball :: FilePath            -- ^ Where to save the tarball.
              -> String              -- ^ Package name.
              -> IO (Maybe FilePath) -- ^ Saved tarball location.
sourceTarball path = saveUrlContents path . tarballUrl

------------
-- RPC CALLS
------------
sortAurInfo :: SortScheme -> [AurInfo] -> [AurInfo]
sortAurInfo scheme ai = sortBy compare' ai
  where compare' = case scheme of
                     ByVote         -> \x y -> compare (aurVotesOf y) (aurVotesOf x)
                     Alphabetically -> \x y -> compare (aurNameOf x) (aurNameOf y)

aurSearch :: T.Text -> Aura [AurInfo]
aurSearch regex = asks sortSchemeOf >>= \scheme ->
                  sortAurInfo scheme <$> search regex

aurInfo :: [T.Text] -> Aura [AurInfo]
aurInfo pkgs = sortAurInfo Alphabetically <$> multiinfo pkgs
