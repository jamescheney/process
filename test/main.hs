import Control.Exception
import Control.Monad (unless)
import System.Exit
import System.IO.Error
import System.Directory (getCurrentDirectory, setCurrentDirectory)
import System.Process
import Data.List (isInfixOf)
import System.IO (hClose, openBinaryTempFile)
import qualified Data.ByteString as S
import qualified Data.ByteString.Char8 as S8
import System.Directory (getTemporaryDirectory, removeFile)

main :: IO ()
main = do
    res <- handle (return . Left . isDoesNotExistError) $ do
        (_, _, _, ph) <- createProcess (proc "definitelydoesnotexist" [])
            { close_fds = True
            }
        fmap Right $ waitForProcess ph
    case res of
        Left True -> return ()
        _ -> error $ show res

    let test name modifier = do
            putStrLn $ "Running test: " ++ name
            (_, _, _, ph) <- createProcess
                $ modifier $ proc "echo" ["hello", "world"]
            ec <- waitForProcess ph
            if ec == ExitSuccess
                then putStrLn $ "Success running: " ++ name
                else error $ "echo returned: " ++ show ec

    test "detach_console" $ \cp -> cp { detach_console = True }
    test "create_new_console" $ \cp -> cp { create_new_console = True }
    test "new_session" $ \cp -> cp { new_session = True }

    putStrLn "Testing subdirectories"

    withCurrentDirectory "exes" $ do
      res1 <- readCreateProcess (proc "./echo.bat" []) ""
      unless ("parent" `isInfixOf` res1 && not ("child" `isInfixOf` res1)) $ error $
        "echo.bat with cwd failed: " ++ show res1

      res2 <- readCreateProcess (proc "./echo.bat" []) { cwd = Just "subdir" } ""
      unless ("child" `isInfixOf` res2 && not ("parent" `isInfixOf` res2)) $ error $
        "echo.bat with cwd failed: " ++ show res2

    putStrLn "Binary handles"
    tmpDir <- getTemporaryDirectory
    bracket
      (openBinaryTempFile tmpDir "process-binary-test.bin")
      (\(fp, h) -> hClose h `finally` removeFile fp)
      $ \(fp, h) -> do
        let bs = S8.pack "hello\nthere\r\nworld\0"
        S.hPut h bs
        hClose h

        (Nothing, Just out, Nothing, ph) <- createProcess (proc "cat" [fp])
            { std_out = CreatePipe
            }
        res' <- S.hGetContents out
        hClose out
        ec <- waitForProcess ph
        unless (ec == ExitSuccess)
            $ error $ "Unexpected exit code " ++ show ec
        unless (bs == res')
            $ error $ "Unexpected result: " ++ show res'

    putStrLn "Tests passed successfully"

withCurrentDirectory :: FilePath -> IO a -> IO a
withCurrentDirectory new inner = do
  orig <- getCurrentDirectory
  bracket_
    (setCurrentDirectory new)
    (setCurrentDirectory orig)
    inner
