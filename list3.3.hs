import System.Environment
import Text.ParserCombinators.Parsec hiding (spaces)
import Control.Monad
import Data.Map as Map hiding (map)
import Numeric
import Data.Char

main = do args <- getArgs
          putStrLn (readExpr (args !! 0))

readExpr :: String -> String
readExpr input = case parse parseExpr "lisp" input of
                   Left err -> "No match: " ++ show err
                   Right val -> "Found value: " ++ show val

data LispVal = Atom String
             | List [LispVal]
             | DottedList [LispVal] LispVal
             | Number Integer
             | String String
             | Bool Bool 
             | Character Char deriving (Show)

parseExpr :: Parser LispVal
parseExpr = parseAtom
            <|> parseString
            <|> parseNumberOrCharacter

parseString :: Parser LispVal
parseString = do char '"'
                 x <- many parseChar
                 char '"'
                 return $ String x

parseChar :: Parser Char
parseChar = do c <- noneOf "\""
               if c == '\\' 
               then parseEscapedChar -- escaped char
               else return c         -- other chars

escapedChars :: Map.Map Char Char
escapedChars = Map.fromList [
                ('\"', '\"'), 
                ('n', '\n'), 
                ('r', '\r'), 
                ('t', '\t'), 
                ('\\', '\\')
               ]

parseEscapedChar :: Parser Char
parseEscapedChar = do c <- satisfy (`Map.member` escapedChars);
                      case Map.lookup c escapedChars of
                        Just x -> return x -- always match

parseAtom :: Parser LispVal
parseAtom = do first <- letter <|> symbol
               rest <- many (letter <|> digit <|> symbol)
               let atom = [first] ++ rest
               return $ case atom of
                          "#t" -> Bool True
                          "#f" -> Bool False
                          otherwise -> Atom atom

parseNumberOrCharacter :: Parser LispVal
parseNumberOrCharacter = do {
                           char '#';
                           parseNumber <|> parseCharacter
                         }
    <|> parseDecNumber

parseNumber :: Parser LispVal
parseNumber = do base <- choice $ map char "bodx"
                 liftM (Number . fst . head) $
                       case base of
                         'b' -> many1 binDigit >>= return . readBin
                         'o' -> many1 octDigit >>= return . readOct
                         'd' -> many1 digit >>= return . readDec
                         'x' -> many1 hexDigit >>= return . readHex

parseDecNumber :: Parser LispVal
parseDecNumber = liftM (Number . read) $ many1 digit

parseCharacter :: Parser LispVal
parseCharacter = do char '\\'
                    c <- anyChar
                    s <- many letter
                    case map toLower (c:s) of
                      [a] -> return $ Character a
                      "space" -> return $ Character ' '
                      "newline" -> return $ Character '\n'
                      x -> (unexpected $ "Invalid character name: " ++ x) <?> "\"newline\" or \"space\""

binDigit :: Parser Char
binDigit = satisfy (`elem` "01")

readBin :: ReadS Integer
readBin = readInt 2 (`elem` "01") digitToInt

symbol :: Parser Char
symbol = oneOf "!$%&|*+-/:<=>?@^_~"

spaces :: Parser ()
spaces = skipMany1 space
