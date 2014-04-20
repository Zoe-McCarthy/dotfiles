import Yi
import Yi.Keymap.Vim
-- import qualified Yi.Keymap.Vim2 as V2
import Yi.Buffer.Indent (indentAsPreviousB)
import Yi.Keymap.Keys
import Yi.Misc (adjBlock)

-- import qualified Yi.UI.Vty

import Yi.Style.Library (darkBlueTheme)
import Data.List (isPrefixOf)
import Control.Monad (replicateM_)
import Control.Applicative

--import Yi.String (modifyLines)

-- import Yi.UI.Vty (start)
-- import Yi.UI.Cocoa (start)
-- import Yi.UI.Pango (start)

-- Uncomment for Shim support
-- import qualified Yi.Mode.Shim as Shim
-- -- Shim.minorMode gives us emacs-like keybindings - what would be a good
-- -- set of keybindings for vim?
-- shimMode :: AnyMode
-- shimMode = AnyMode (Shim.minorMode Haskell.cleverMode)

{-
  For now we just make the selected style the same as the
  modeline_focused style... Just because i'm not good with
  styles yet - Jim
-}

{-
--default vimstuffs
defaultVimUiTheme :: Theme
defaultVimUiTheme = defaultTheme  `override` \super self -> super {
        selectedStyle = modelineFocusStyle self
 }

myConfigUI :: UIConfig
myConfigUI = (configUI defaultVimConfig)  {
        configFontSize = Just 10,
        configTheme = defaultVimUiTheme,
        configWindowFill = '~'
 }
-}

main :: IO ()
main = yi $ config


-- | Increase the indentation of the selection    
--increaseIndent :: BufferM ()
--increaseIndent = do
  --r <- getSelectRegionB 
  --r' <- unitWiseRegion Line r 
     -- extend the region to full lines
  --modifyRegionB (modifyLines (' ':)) r'
     -- prepend each line with a space}



-- Set soft tabs of 4 spaces in width.
prefIndent :: Mode s -> Mode s
prefIndent m = m {
        modeIndentSettings = IndentSettings
            {
                expandTabs = True,
                shiftWidth = 4,
                tabSize = 4
            }}

noHaskellAnnots m 
    | modeName m == "haskell" = m { modeGetAnnotations = modeGetAnnotations emptyMode }
    | otherwise = m

config = defaultConfig 
    {
        -- Use VTY as the default UI.
        -- startFrontEnd = Yi.UI.Vty.start,
        defaultKm = mkKeymap extendedVimKeymap,
        modeTable = fmap (onMode $ noHaskellAnnots . prefIndent) (modeTable defaultConfig),
        configUI = (configUI defaultConfig)
            {
                configTheme = darkBlueTheme
            }
    }

extendedVimKeymap = defKeymap `override` \super self -> super
    {
        v_top_level = 
            (deprioritize >> v_top_level super)
            -- On 'o' in normal mode I always want to use the indent of the previous line.
            -- TODO: If the line where the newline is to be inserted is inside a
            -- block comment then the block comment should be "continued"
            -- TODO: Ends up I'm trying to replicate vim's "autoindent" feature. This 
            -- should be made a function in Yi.
            <|> (char 'o' ?>> beginIns self $ do 
                    moveToEol
                    insertB '\n'
                    indentAsPreviousB
                )
            -- TODO: fix for clearing search space: 
            -- <|> (char ' ' >> V2.pureEval self ":nohlsearch<CR>")
            -- 
            -- TODO: make ; work to continue search on the line of f/F
            --
            -- TODO: type displaying somehow
            --
            -- On HLX (Haskell Language Extension) I want to go into insert mode such 
            -- that the cursor position is correctly placed to start entering the name
            -- of an language extension in a LANGUAGE pragma.
            -- A language pragma will take either the form
            -- {-# LANGUAGE Foo #-}
            -- or
            -- >{-# LANGUAGE Foo #-}
            -- The form should be chosen based on the current mode.
            <|> ( pString "HXL" >> startExtensionNameInsert self ),
        v_ins_char = 
            (deprioritize >> v_ins_char super) 
            -- On enter I always want to use the indent of previous line
            -- TODO: If the line where the newline is to be inserted is inside a
            -- block comment then the block comment should be "continued"
            -- TODO: Ends up I'm trying to replicate vim's "autoindent" feature. This 
            -- should be made a function in Yi.
            <|> ( spec KEnter ?>>! do
                    insertB '\n'
                    indentAsPreviousB
                )
            -- I want softtabs to be deleted as if they are tabs. So if the 
            -- current col is a multiple of 4 and the previous 4 characters
            -- are spaces then delete all 4 characters.
            -- TODO: Incorporate into Yi itself.
            <|> ( spec KBS ?>>! do
                    c <- curCol
                    line <- readRegionB =<< regionOfPartB Line Backward
                    sw <- indentSettingsB >>= return . shiftWidth
                    let indentStr = replicate sw ' '
                        toDel = if (c `mod` sw) /= 0
                                    then 1
                                    else if indentStr `isPrefixOf` reverse line 
                                        then sw
                                        else 1
                    adjBlock (-toDel)
                    replicateM_ toDel $ deleteB Character Backward
                )
            -- On starting to write a block comment I want the close comment 
            -- text inserted automatically.
            <|> choice 
                [ pString open_tag >>! do
                    insertN $ open_tag ++ " \n" 
                    indentAsPreviousB
                    insertN $ " " ++ close_tag
                    lineUp
                 | (open_tag, close_tag) <- 
                    [ ("{-", "-}") -- Haskell block comments
                    , ("/*", "*/") -- C++ block comments
                    ]
                ]
    }


startExtensionNameInsert :: ModeMap -> I Event Action ()
startExtensionNameInsert self = beginIns self $ do
    p_current <- pointB
    m_current <- getMarkB (Just "'") 
    setMarkPointB m_current p_current
    moveTo $ Point 0
    insertB '\n'
    moveTo $ Point 0
    insertN "{-# LANGUAGE "
    p <- pointB
    insertN " #-}"
    moveTo p

