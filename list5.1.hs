import System.Environment
import Text.ParserCombinators.Parsec hiding (spaces)
import Control.Monad
import Data.Map as Map hiding (map)
import Numeric
import Data.Char hiding (isSymbol, isNumber)
import Control.Monad.Error

main = getArgs >>= putStrLn . extractValue . trapError . (liftM (show . eval)) . readExpr . (!!0)

readExpr :: String -> ThrowsError LispVal
readExpr input = case parse parseExpr "lisp" input of
                   Left err -> throwError $ Parser err
                   Right val -> return val

data LispVal = Atom String
             | List [LispVal]
             | DottedList [LispVal] LispVal
             | Number Integer
             | String String
             | Bool Bool 
             | Character Char 
             | Array [LispVal] 

data LispError = NumArgs Integer [LispVal]
               | TypeMismatch String LispVal
               | Parser ParseError
               | BadSpecialForm String LispVal
               | NotFunction String String
               | UnboundVar String String
               | Default String

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

eval :: LispVal -> ThrowsError LispVal
eval val@(String _) = return val
eval val@(Number _) = return val
eval val@(Bool _) = return val
eval val@(Character _) = return val
eval (Atom s) = case Prelude.lookup s primitives of
                      Just _ -> return $ Atom "#primitive"
                      Nothing -> throwError $ UnboundVar "Unbound variable" s
eval (List [Atom "quote", val]) = return val
eval (List (Atom func : args)) = mapM eval args >>= apply func

apply :: String -> [LispVal] -> ThrowsError LispVal
apply func args = maybe (throwError $ NotFunction "Unrecognized primitive function args" func) 
                  ($ args) $ Prelude.lookup func primitives

primitives :: [(String, [LispVal] -> ThrowsError LispVal)]
primitives = [("+", numericBinop (+)),
              ("-", numericBinop (-)),
              ("*", numericBinop (*)),
              ("/", numericBinop div),
              ("mod", numericBinop mod),
              ("quotient", numericBinop quot),
              ("remainder", numericBinop rem),
              ("symbol?", isSymbol),
              ("string?", isString),
              ("number?", isNumber),
              ("symbol->string", symbolToString)]

numericBinop :: (Integer -> Integer -> Integer) -> [LispVal] -> ThrowsError LispVal
numericBinop op singleVal@[_] = throwError $ NumArgs 2 singleVal
numericBinop op params = mapM unpackNum params >>= return . Number . foldl1 op

unpackNum :: LispVal -> ThrowsError Integer
unpackNum (Number n) = return n
unpackNum notNum = throwError $ TypeMismatch "number" notNum

isSymbol :: [LispVal] -> ThrowsError LispVal
isSymbol [Atom _] = return $ Bool True
isSymbol [(List [Atom "quote", Atom _])] = return $ Bool True
isSymbol _ = return $ Bool False

isString :: [LispVal] -> ThrowsError LispVal
isString [String _] = return $ Bool True
isString _ = return $ Bool False

isNumber :: [LispVal] -> ThrowsError LispVal
isNumber [Number _] = return $ Bool True
isNumber _ = return $ Bool False

symbolToString :: [LispVal] -> ThrowsError LispVal
symbolToString emptyVal@[] = throwError $ NumArgs 1 emptyVal
symbolToString [Atom s] = return $ String s
symbolToString [(List [Atom "quote", Atom val])] = return $ String val
symbolToString [notSymbol] = throwError $ TypeMismatch "symbol" notSymbol
symbolToString x@(a:b:bs) = throwError $ NumArgs 1 x

showError :: LispError -> String
showError (UnboundVar message varname) = message ++ ": " ++ varname
showError (BadSpecialForm message form) = message ++ ": " ++ show form
showError (NotFunction message func) = message ++ ": " ++ show func
showError (NumArgs expected found) = "Expected " ++ show expected 
                                  ++ " args; found values " ++ unwordsList found
showError (TypeMismatch expected found) = "Invalid type: expected " ++ expected
                                       ++ ", found " ++ show found
showError (Parser parseErr) = "Parse error at " ++ show parseErr

instance Show LispError where show = showError

instance Error LispError where
    noMsg = Default "An error has occurred"
    strMsg = Default

type ThrowsError = Either LispError

trapError action = catchError action (return . show)

extractValue :: ThrowsError a -> a
extractValue (Right val) = val
