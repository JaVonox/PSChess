@echo off
for /L %%i in (1,1,8) do (
    start powershell.exe -executionpolicy remotesigned -NoExit -File ChessTest.ps1
)