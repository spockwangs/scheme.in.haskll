import System.Environment
import Text.ParserCombinators.Parsec hiding (spaces)
import Control.Monad
import Data.Map as Map hiding (map)
import Numeric
import Data.Char

main = getArgs >>= putStrLn . show . eval . readExpr . (!!0)

readExpr :: String -> LispVal
readExpr input = case parse parseExpr "lisp" input of
                   Left err -> String $ "No match: " ++ show err
                   Right val -> val

data LispVal = Atom String
             | List [LispVal]
             | DottedList [LispVal] LispVal
             | Number Integer
             | String String
             | Bool Bool 
             | Character Char 
             | Array [LispVal] 

parseExpr :: Parser LispVal
parseExpr = parseAtom
            <|> parseString   -- begin with "
            <|> do char '#'
                   parseBool <|> parseNumber <|> parseCharacter <|> parseArray
            <|> parseDecNumber -- begin with a digit
            <|> parseQuoted    -- begin with '
            <|> parseBackquoted -- begin with `
            <|> do char '('
                   x <- (try parseList) <|> parseDottedList
                   char ')'
                   return x

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
               return $ Atom atom

parseBool :: Parser LispVal
parseBool = do c <- choice $ map char "tf"
               return $ case c of
                          't' -> Bool True
                          'f' -> Bool False

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

parseArray :: Parser LispVal
parseArray = do char '('
                x <- sepBy parseExpr spaces
                char ')'
                return $ Array x

binDigit :: Parser Char
binDigit = satisfy (`elem` "01")

readBin :: ReadS Integer
readBin = readInt 2 (`elem` "01") digitToInt

symbol :: Parser Char
symbol = oneOf "!$%&|*+-/:<=>?@^_~"

spaces :: Parser ()
spaces = skipMany1 space

parseList :: Parser LispVal
parseList = liftM List $ sepBy parseExpr spaces

parseDottedList :: Parser LispVal
parseDottedList = do head <- endBy parseExpr spaces
                     tail <- char '.' >> spaces >> parseExpr
                     return $ DottedList head tail

parseQuoted :: Parser LispVal
parseQuoted = do char '\''
                 x <- parseExpr
                 return $ List [Atom "quote", x]

parseBackquoted :: Parser LispVal
parseBackquoted = do char '`'
                     x <- parseExpr
                     return $ List [Atom "quasiquote", x]

instance Show LispVal where
    show (String contents) = "\"" ++ contents ++ "\""
    show (Atom name) = name
    show (Number contents) = show contents
    show (Bool True) = "#t"
    show (Bool False) = "#f"
    show (List contents) = "(" ++ unwordsList contents ++ ")"
    show (DottedList head tail) = "(" ++ unwordsList head ++ " . " ++ show tail ++ ")"

unwordsList :: [LispVal] -> String
unwordsList = unwords . map show

eval :: LispVal -> LispVal
eval val@(String _) = val
eval val@(Number _) = val
eval val@(Bool _) = val
eval (List [Atom "quote", val]) = val
