import System.Environment
import Text.ParserCombinators.Parsec hiding (spaces)

main = do args <- getArgs
          putStrLn (readExpr (args !! 0))

symbol :: Parser Char
symbol = oneOf "!$%&|*+-/:<=>?@^_~"

readExpr :: String -> String
readExpr input = case parse symbol "lisp" input of
                   Left err -> "No match: " ++ show err
                   Right val -> "Found value: " ++ show val
