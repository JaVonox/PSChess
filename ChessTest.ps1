﻿#Game constructs
enum Allegiance
{
    None
    White
    Black
}

#Movements
class Position {
    [int]$X
    [int]$Y

    Position([int]$nX, [int]$nY) {
        $this.X = $nX
        $this.Y = $nY
    }

    [bool] Equals([object]$obj) {
        if ($obj -isnot [Position]) { return $false }
        return $this.X -eq $obj.X -and $this.Y -eq $obj.Y
    }

    [int] GetHashCode() {
        return ($this.X -shl 3) -bor $this.Y
    }
}

class MoveVsScore{
    [Position]$Pos
    [int]$ScoreChange

    MoveVsScore()
    {
        
    }

    MoveVsScore([Position]$nPos,[int]$nScoreChange)
    {
        $this.Pos = $nPos
        $this.ScoreChange = $nScoreChange
    }
}

class IMoveRule {
    [System.Collections.Generic.List[MoveVsScore]] GetPossibleMoves([Position]$from, [Allegiance]$allegiance, $board) {
        throw "Must be implemented"
    }
}

#Movement Rules

class DirectionalRule : IMoveRule
{
    [int]$DirX
    [int]$DirY
    [bool]$Repeating
    
    DirectionalRule([int]$dx,[int]$dy,[bool]$repeating)
    {
        $this.DirX = $dx;
        $this.DirY = $dy;
        $this.Repeating = $repeating;
    }

    [System.Collections.Generic.List[MoveVsScore]] GetPossibleMoves([Position]$from,[Allegiance]$myAllegiance,$board)
    {
        $moves = [System.Collections.Generic.List[MoveVsScore]]::new()
        $x = $from.x + $this.DirX;
        $y = $from.y + $this.DirY;
        
        while($x -ge 0 -and $x -lt 8 -and $y -ge 0 -and $y -lt 8)
        {
            $pos = [Position]::new($x,$y);
            if($board[$x,$y].OccupantAllegiance -ne [Allegiance]::None) #If there is an occupant on this tile
            {
                if($board[$x,$y].OccupantAllegiance -ne $myAllegiance)
                {
                    $moves.Add([MoveVsScore]::new($pos,$($board[$x,$y].GetTakingScore($myAllegiance))))
                }
                break;
            }
            
            $moves.Add([MoveVsScore]::new($pos,0))
            
            if(-not $this.Repeating)
            {
                break;
            }
            
            $x += $this.DirX;
            $y += $this.DirY;
        }
        
        return $moves;
    }
}

class SpecialRule : IMoveRule
{
    [scriptBlock]$Condition
    [scriptblock]$MoveGenerator
    
    SpecialRule([scriptBlock]$newCondition,[scriptBlock]$newMoveGen)
    {
        $this.Condition = $newCondition;
        $this.MoveGenerator = $newMoveGen;
    }

    [System.Collections.Generic.List[MoveVsScore]] GetPossibleMoves([Position]$from, [Allegiance]$allegiance, $board) {
        if(& $this.Condition $from $allegiance $board) #& operator executes $this.Condition as a script using the parameters given
        {
            return & $this.MoveGenerator $from $allegiance $board
        }
        return [System.Collections.Generic.List[MoveVsScore]]::new();
    }
}

class CompositeRule : IMoveRule
{
    [IMoveRule[]]$Rules
    
    CompositeRule([IMoveRule[]]$ComponentRules)
    {
        $this.Rules = $ComponentRules
    }

    [System.Collections.Generic.List[MoveVsScore]] GetPossibleMoves([Position]$from, [Allegiance]$allegiance, $board) {
        $allMoves = [System.Collections.Generic.List[MoveVsScore]]::new()
        foreach($rule in $this.Rules)
        {
            $moves = $rule.GetPossibleMoves($from,$allegiance,$board)
            foreach($move in $moves)
            {
                $allMoves.Add($move)
            }
        }
        return $allMoves
    }
}

class PostMoveEffect
{
    [scriptBlock]$Condition
    [scriptBlock]$Effect
    [int]$ScoreChangeIfApplied

    PostMoveEffect()
    {

    }

    PostMoveEffect([scriptBlock]$nCondition,[scriptBlock]$nEffect,[int]$nScoreChange)
    {
        $this.Condition = $nCondition
        $this.Effect = $nEffect
        $this.ScoreChangeIfApplied = $nScoreChange
    }
    
    #Used when we are evaluating the score change based on moves to 
    [float] AddScoreToMove($newPosition, $allegiance, $board)
    {
        if(& $this.Condition $newPosition $allegiance $board) {return $this.ScoreChangeIfApplied}
        return 0
    }
    
    #Actually Computes the result of the action
    [bool] DoEffect($newPosition, $allegiance, $board)
    {
        if(& $this.Condition $newPosition $allegiance $board)
        {
            Write-Host "DOING EFFECT"
            & $this.Effect $newPosition $allegiance $board
            
            return $true
        }
        return $false
    }
}

class MoveCache
{
    [hashtable]$cachedMoves = @{}
    [string]$AIMove
    [int]$SearchDepth
    

    hidden [string] GetMoveKey([Position]$from, [Position]$to) {
        return ($from.X) -bor ($from.Y -shl 3) -bor ($to.X -shl 6) -bor ($to.Y -shl 9)
    }

    # Parse a move key back into positions
    hidden [bool] ParseMoveKey([int]$moveKey,[ref]$from,[ref]$to) {
        # Extract values using masks
        # 0x7 is binary 111 (3 bits)
        $fromX = $moveKey -band 0x7          # First 3 bits
        $fromY = ($moveKey -shr 3) -band 0x7 # Next 3 bits
        $toX = ($moveKey -shr 6) -band 0x7   # Next 3 bits
        $toY = ($moveKey -shr 9) -band 0x7   # Final 3 bits
        
        $from.Value = [Position]::new($fromX, $fromY)
        $to.Value = [Position]::new($toX, $toY)
        return $true
    }
    
    #Return average non zero score. Do Checks 
    [float] UpdateCache([Allegiance]$PlayerAllegiance,$Tiles,[int]$DoChecks,[ref]$MoveCounter)
    {
        $this.SearchDepth = $DoChecks
        
        [System.Collections.Generic.List[string]]$BestMoves = [System.Collections.Generic.List[string]]::new()
        [float]$BestMoveScore = [float]::MinValue
        [float]$CumulativeScore = 0
        
        $this.cachedMoves.Clear()
        $this.AIMove = ""

        For ($y = 0; $y -le 7; $y++) {
            For ($x = 0; $x -le 7; $x++) {
                if ($PlayerAllegiance -eq $Tiles[$x, $y].OccupantAllegiance)
                {
                    $CurrentPosition = [Position]::new($x, $y)
                    [System.Collections.Generic.List[MoveVsScore]]$moves = $Tiles[$x, $y].GetMoves($CurrentPosition, $PlayerAllegiance, $Tiles)
                    $mL = $moves.Count

                    foreach ($moveTarget in $moves)
                    {
                        $MoveCounter.Value = $MoveCounter.Value + 1
                        $moveScore = [float]($moveTarget.ScoreChange)
                        $moveScore += $($Tiles[$x,$y].OccupantPiece::PostMove.AddScoreToMove($moveTarget.Pos,$PlayerAllegiance,$Tiles))
                        $moveKey = $this.GetMoveKey($CurrentPosition, $moveTarget.Pos)
                        
                        #Only the AI will have greater than 0 depth ever
                        if ($this.SearchDepth -gt 0)
                        {
                            $lookAheadScore = $this.GetDepthScore($CurrentPosition, $moveTarget.Pos, $Tiles, $this, $PlayerAllegiance, $MoveCounter)

                            $moveScore += $lookAheadScore
                        }

                        $this.cachedMoves[$moveKey] = $moveScore
                        
                        if ($moveScore -gt $BestMoveScore)
                        {
                            $BestMoves.Clear()
                            $BestMoves.Add($moveKey)
                            $BestMoveScore = $moveScore
                        }
                        elseif ($moveScore -eq $BestMoveScore)
                        {
                            $BestMoves.Add($moveKey)
                        }
                    }
                }
            }
        }

        if ($BestMoves.Count -gt 0) {
            $this.AIMove = $BestMoves[(Get-Random -Maximum $BestMoves.Count)]
            return $BestMoveScore
        }
        
        return 0
    }
    
    #Add negative average of non 0
    [float] GetDepthScore([Position]$FromPos,[Position]$ToPos,$Tiles,$MoveCache,[Allegiance]$PlayerAllegiance,[ref]$MoveCounter)
    {
        # Create deep copy of board
        $TilesInstance = New-Object 'Tile[,]' 8,8

        for ($y = 0; $y -lt 8; $y++) {
            for ($x = 0; $x -lt 8; $x++) {
                $TilesInstance[$x,$y] = $Tiles[$x,$y].Clone()
            }
        }
        
        $moveResult = $TilesInstance[$FromPos.X, $FromPos.Y].MovePiece($FromPos, $ToPos, $TilesInstance, $this,$true)

        if (-not $moveResult) {
            Write-Host "Invalid move, returning 0"
            return 0
        }

        $CacheInstance = [MoveCache]::new()

        $OpponentAllegiance = $(If($PlayerAllegiance -eq [Allegiance]::White) {[Allegiance]::Black} else {[Allegiance]::White})

        [int]$NewDepth = $this.SearchDepth - 1
        
        $depthScore = $CacheInstance.UpdateCache($OpponentAllegiance, $TilesInstance, $NewDepth,$MoveCounter)

        $finalScore = $(If($this.SearchDepth % 2 -eq 0) { $depthScore } else { -$depthScore })

        return $finalScore
    }
    
    [bool] IsValidMove([Position]$FromPosition,[Position]$TargetPosition)
    {
        $moveKey = $this.GetMoveKey($FromPosition, $TargetPosition)
        return $this.cachedMoves.ContainsKey($moveKey)
    }
    
    [bool] GetAIMove([ref]$FromPosition,[ref]$TargetPosition)
    {
        return $this.ParseMoveKey($this.AIMove,$FromPosition,$TargetPosition)
    }
    
}
#Pieces

class PieceTypeBase
{
    static [char]$pieceIcon = 'N';
    static [int]$pieceValue = 0;
    static [CompositeRule]$PieceRules = @{}
    static [PostMoveEffect]$PostMove = @{}
}

class Pawn : PieceTypeBase
{
    static [char]$pieceIcon = '♙';
    static [int]$pieceValue = 1;
    static [CompositeRule]$PieceRules = [CompositeRule]::new(@([SpecialRule]::new(
    {
        #pawn moves away from its own side and can move twice on first turn
        param($from, $allegiance, $board) $true
    },
    {
        param($from, $allegiance, $board)
        $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
        if ($board[$from.X, $($from.Y + $MovementDirection)].OccupantAllegiance -eq [Allegiance]::None)
        {
            $moves = [System.Collections.Generic.List[MoveVsScore]]::new()
            
            $firstMove = [Position]::new($from.X, $($from.Y + $MovementDirection))
            $moves.Add([MoveVsScore]::new($firstMove,$($Tiles[$from.X,$($from.Y + $MovementDirection)].GetTakingScore($allegiance))))
            
            if(($allegiance -eq [Allegiance]::White -and $from.Y -eq 6) -or ($allegiance -eq [Allegiance]::Black -and $from.Y -eq 1))
            {
                if ($board[$from.X, $($from.Y + $($MovementDirection * 2))].OccupantAllegiance -eq [Allegiance]::None)
                {
                    $secondMove = [Position]::new($from.X, $($from.Y + $MovementDirection * 2))
                    $moves.Add([MoveVsScore]::new($secondMove,$($Tiles[$from.X,$($MovementDirection * 2)].GetTakingScore($allegiance))))
                }
            }
            return $moves
        }
        return [System.Collections.Generic.List[MoveVsScore]]::new()
    }),[SpecialRule]::new( #Check right diagonal
        { 
            param($from, $allegiance, $board)
            $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
            $OppositeAllegiance = $(If($allegiance -eq [Allegiance]::White) {[Allegiance]::Black} Else {[Allegiance]::White})
            $x = $from.X + 1 
            $y = $from.Y + $MovementDirection
            return $x -lt 8 -and $y -lt 8 -and $board[$x,$y].OccupantAllegiance -eq $OppositeAllegiance
        },
        {
            param($from, $allegiance, $board)
            $moves = [System.Collections.Generic.List[MoveVsScore]]::new()
            $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
            $newPos = [Position]::new($($from.X + 1), $($from.Y + $MovementDirection))
            [int]$rScore = $board[$newPos.X, $newPos.Y].GetTakingScore($allegiance)
            $moves.Add([MoveVsScore]::new($newPos, $rScore))
            return $moves
        })
        ,[SpecialRule]::new( #Check left diagonal
        {
            param($from, $allegiance, $board)
            $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
            $OppositeAllegiance = $(If($allegiance -eq [Allegiance]::White) {[Allegiance]::Black} Else {[Allegiance]::White})
            $x = $from.X - 1
            $y = $from.Y + $MovementDirection
            return $x -lt 8 -and $y -lt 8 -and $board[$x,$y].OccupantAllegiance -eq $OppositeAllegiance
        },
        {
            param($from, $allegiance, $board)
            $moves = [System.Collections.Generic.List[MoveVsScore]]::new()
            $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
            $newPos = [Position]::new($($from.X - 1), $($from.Y + $MovementDirection))
            [int]$lScore = $board[$newPos.X, $newPos.Y].GetTakingScore($allegiance)
            $moves.Add([MoveVsScore]::new($newPos, $lScore))
            return $moves
        })
    ))
    static [PostMoveEffect]$PostMove = [PostMoveEffect]::new(
    {
        param($newPosition, $allegiance, $board)
        return (($allegiance -eq [Allegiance]::White -and $newPosition.Y -eq 0) -or ($allegiance -eq [Allegiance]::Black -and $newPosition.Y -eq 7))
    },
    {
        param($newPosition, $allegiance, $board)
        $board[$newPosition.X,$newPosition.Y].OccupantPiece = [Queen]
    }, 8)
    
    
    #TODO ADD EN PASSANT
}

class Rook : PieceTypeBase
{
    static [char]$pieceIcon = '♖';
    static [int]$pieceValue = 5;
    static [CompositeRule]$PieceRules = [CompositeRule]::new(@([DirectionalRule]::new(1,0,$true),[DirectionalRule]::new(-1,0,$true),
    [DirectionalRule]::new(0,1,$true),[DirectionalRule]::new(0,-1,$true)));
    static [PostMoveEffect]$PostMove = [PostMoveEffect]::new({param($newPosition, $allegiance, $board)return $false},{param($newPosition, $allegiance, $board)},0)
    
    #TODO ADD CASTLING
}

class Knight : PieceTypeBase
{
    static [char]$pieceIcon = '♘';
    static [int]$pieceValue = 3;
    static [CompositeRule]$PieceRules = [CompositeRule]::new(@([DirectionalRule]::new(2,1,$false),[DirectionalRule]::new(2,-1,$false),
    [DirectionalRule]::new(-2,1,$false),[DirectionalRule]::new(-2,-1,$false),
            [DirectionalRule]::new(1,2,$false),[DirectionalRule]::new(1,-2,$false),
            [DirectionalRule]::new(-1,2,$false),[DirectionalRule]::new(-1,-2,$false)));
    static [PostMoveEffect]$PostMove = [PostMoveEffect]::new({param($newPosition, $allegiance, $board)return $false},{param($newPosition, $allegiance, $board)},0)
}

class Bishop : PieceTypeBase
{
    static [char]$pieceIcon = '♗';
    static [int]$pieceValue = 3;
    static [CompositeRule]$PieceRules = [CompositeRule]::new(@([DirectionalRule]::new(1,1,$true),[DirectionalRule]::new(1,-1,$true),
    [DirectionalRule]::new(-1,1,$true),[DirectionalRule]::new(-1,-1,$true)));
    static [PostMoveEffect]$PostMove = [PostMoveEffect]::new({param($newPosition, $allegiance, $board)return $false},{param($newPosition, $allegiance, $board)},0)
}

class King : PieceTypeBase
{
    static [char]$pieceIcon = '♔';
    static [int]$pieceValue = 1000;
    static [CompositeRule]$PieceRules = [CompositeRule]::new(@(
        [DirectionalRule]::new(1, 0, $false),
        [DirectionalRule]::new(-1, 0, $false),
        [DirectionalRule]::new(0, 1, $false),
        [DirectionalRule]::new(0, -1, $false),
        [DirectionalRule]::new(1, 1, $false),
        [DirectionalRule]::new(1, -1, $false),
        [DirectionalRule]::new(-1, 1, $false),
        [DirectionalRule]::new(-1, -1, $false)
    ))
    static [PostMoveEffect]$PostMove = [PostMoveEffect]::new({param($newPosition, $allegiance, $board)return $false},{param($newPosition, $allegiance, $board)},0)

    #TODO ADD RULE PREVENTING PUTTING SELF IN CHECK
    #TODO ADD CASTLING?
}

class Queen : PieceTypeBase
{
    static [char]$pieceIcon = '♕';
    static [int]$pieceValue = 9;
    static [CompositeRule]$PieceRules = [CompositeRule]::new(@(
        [DirectionalRule]::new(1, 0, $true),
        [DirectionalRule]::new(-1, 0, $true),
        [DirectionalRule]::new(0, 1, $true),
        [DirectionalRule]::new(0, -1, $true),
        [DirectionalRule]::new(1, 1, $true),
        [DirectionalRule]::new(1, -1, $true),
        [DirectionalRule]::new(-1, 1, $true),
        [DirectionalRule]::new(-1, -1, $true)
    ))
    static [PostMoveEffect]$PostMove = [PostMoveEffect]::new({param($newPosition, $allegiance, $board)return $false},{param($newPosition, $allegiance, $board)},0)
}

class Tile
{
    [System.Type]$OccupantPiece
    [Allegiance]$OccupantAllegiance;
    [bool]$IsWhiteTile;

    Tile($NewOccupantType,$NewOccupantAllegiance,$NewBackIsWhite)
    {
        $this.OccupantPiece = $NewOccupantType;
        $this.OccupantAllegiance = $NewOccupantAllegiance;
        $this.IsWhiteTile = $NewBackIsWhite;
    }

    [bool] CheckCanMoveTo([Position]$FromPos,[Position]$ToPos,$Tiles,$MoveCache)
    {
        return $this.OccupantAllegiance -ne [Allegiance]::None -and $MoveCache.IsValidMove($FromPos,$ToPos);
    }

    [System.Collections.Generic.List[MoveVsScore]] GetMoves([Position]$from, [Allegiance]$allegiance, $board)
    {
        return $this.OccupantPiece::PieceRules.GetPossibleMoves($from, $allegiance, $board)
    }
    
    [int] GetTakingScore([Allegiance]$senderAllegiance)
    {
        if($this.OccupantAllegiance -ne [Allegiance]::None)
        {
            if($this.OccupantAllegiance -ne $senderAllegiance)
            {
                return $this.OccupantPiece::pieceValue
            }
        }
        return 0;
    }

    [char] GetIcon()
    {
        if($this.OccupantAllegiance -eq [Allegiance]::None)
        {
            return ' '
        }
        else
        {
            return $this.OccupantPiece::pieceIcon
        }
    }

    [bool] MovePiece([Position]$FromPos,[Position]$ToPos,$Tiles,$MoveCache,$IgnoreCheck)
    {
        if($IgnoreCheck -or $this.CheckCanMoveTo($FromPos,$ToPos,$Tiles,$MoveCache))
        {
            #Swap Pieces
            $Tiles[$ToPos.X,$ToPos.Y].OccupantPiece = $this.OccupantPiece;
            $this.OccupantPiece = $null;
            $newAllegiance = $this.OccupantAllegiance
            $Tiles[$ToPos.X,$ToPos.Y].OccupantAllegiance = $newAllegiance;
            $this.OccupantAllegiance = [Allegiance]::None;
            
            #Do post move effect e.g become queen if pawn 
            $Tiles[$ToPos.X,$ToPos.Y].OccupantPiece::PostMove.DoEffect($ToPos,$newAllegiance,$Tiles)
            
            return $true;
        }
        else
        {
            return $false;
        }
    }

    [Tile] Clone() {
        return [Tile]::new(
                $this.OccupantPiece,  # Type reference is okay to copy directly
                $this.OccupantAllegiance,
                $this.IsWhiteTile
        )
    }
}

function GenerateBaseGrid($Tiles)
{
    $IndexTyping = @([Rook],[Knight],[Bishop],[Queen],[King],[Pawn]);
    for ($y = 1; $y -le 8; $y++) {
        $IsWhiteBarracks = ($y -ge 7);
        for ($x = 1; $x -le 8; $x++) {
            $TileOccupantIndex = [int]($y -eq 1 -or $y -eq 8) * $(If($x -le 5) {$x} Else {8-$x+1}) + ([int]($y -eq 2 -or $y -eq 7) * 6) - 1;

            $NewOccupantType = $null
            $Allegiance = [Allegiance]::None;
            if($TileOccupantIndex -ge 0)
            {
                $NewOccupantType = $IndexTyping[$TileOccupantIndex];
                $Allegiance = If($IsWhiteBarracks){[Allegiance]::White}Else{[Allegiance]::Black};
            }
            $Tiles[$($x-1),$($y-1)] = [Tile]::new($NewOccupantType,$Allegiance,((($y-1) + ($x-1)) % 2) -eq 1);
        }
    }
}

function ParseNotation([string]$notation,[ref]$ToPos,[ref]$FromPos,[ref]$TargetPiece,[ref]$IsMoveCheck)
{
    #notation to check if valid move
    if($($notation -match "([KQRBN])?([abcdefgh?])([12345678])([abcdefgh?])([12345678?])"))
    {
        switch($Matches[1])
        {
            "K" {$TargetPiece.Value = [King];break;}
            "Q" {$TargetPiece.Value = [Queen];break;}
            "R" {$TargetPiece.Value = [Rook];break;}
            "B" {$TargetPiece.Value = [Bishop];break;}
            "N" {$TargetPiece.Value = [Knight];break;}
            "" {$TargetPiece.Value = [Pawn];break;}
        }
        
        $FromPos.Value.X = [char]($Matches[2]) % 97; #X values are alphabetical, % 97 returns their position in the alphabet zero indexed
        $FromPos.Value.Y = 7 - ($Matches[3] - 1);
        
        if($Matches[4] -eq "?") #Check Moves Call
        {
            $ToPos.Value.X = 0 
            $ToPos.Value.Y = 0
            $IsMoveCheck.Value = $true
        }
        else
        {
            $ToPos.Value.X = [char]($Matches[4]) % 97 #X values are alphabetical, % 97 returns their position in the alphabet zero indexed
            $ToPos.Value.Y = 7 - ($Matches[5] - 1)
            $IsMoveCheck.Value = $false
        }
        return $true
    }
    else
    {
        return $false
    }

}


[Tile[,]]$Grid = New-Object 'Tile[,]' 8,8

GenerateBaseGrid $Grid
$moveCache = [MoveCache]::new()

$continue = $true
$whitesTurn = $true
while($continue)
{
    #Clear-Host
    $AIDepth = $(If($whitesTurn){0}else{0}) #Else as 1 for AI 

    Write-Host $(If($whitesTurn) {"Your Turn"} Else {"Enemy Thinking..."});
    
    $totalMoves = 0
    $maxScore = $moveCache.UpdateCache($(If($whitesTurn){[Allegiance]::White}else{[Allegiance]::Black}),$Grid,$AIDepth,[ref]$totalMoves)
    Write-Host "Possible Moves $totalMoves maxScore $maxScore"
    
    Write-Host " a b c d e f g h ";

    For ($y = 0; $y -le 7;$y++)
    {
        Write-Host $([Math]::Abs($y-8)) -NoNewLine
        For ($x = 0; $x -le 7;$x++)
        {
            $output = $Grid[$x,$y].GetIcon() + " "
            [System.ConsoleColor]$colour = $(If($Grid[$x,$y].IsWhiteTile){[System.ConsoleColor]::DarkYellow}else{[System.ConsoleColor]::DarkRed})
            [System.ConsoleColor]$pieceColour = $(If($Grid[$x,$y].OccupantAllegiance -eq [Allegiance]::White){[System.ConsoleColor]::White}else{[System.ConsoleColor]::Black})
            Write-Host $output -NoNewLine -BackgroundColor $colour -ForegroundColor $pieceColour
        }
        Write-Host " "
    }
    
    if($whitesTurn)
    {
        while ($true)
        {
            Write-Host " "
            $Move = Read-Host "Enter Move";

            if ($Move -eq "exit")
            {
                $continue = $false;
                break;
            }
            else
            {
                #Target for movement
                [Position]$selectedTarget = [Position]::new(0, 0)
                #Current Position
                [Position]$currentPosition = [Position]::new(0, 0)
                #Expected Piece
                $selectedTargetPiece = $null
                #If Move Query
                [bool]$IsMoveQuery = $true
                if (ParseNotation $Move ([ref]$selectedTarget) ([ref]$currentPosition) ([ref]$selectedTargetPiece) ([ref]$IsMoveQuery))
                {
                    if ($IsMoveQuery -and $Grid[$currentPosition.X, $currentPosition.Y].OccupantAllegiance -eq $( If ($whitesTurn) {[Allegiance]::White } else {[Allegiance]::Black } ))
                    {
                        Clear-Host
                        Write-Host $( If ($whitesTurn)
                        {
                            "Whites Turn"
                        }
                        Else
                        {
                            "Blacks Turn"
                        } );
                        Write-Host " a b c d e f g h "
                        For ($y = 0; $y -le 7; $y++)
                        {
                            Write-Host $([Math]::Abs($y - 8) ) -NoNewLine
                            For ($x = 0; $x -le 7; $x++)
                            {
                                [System.ConsoleColor]$colour = $( If ( $moveCache.IsValidMove($currentPosition,[Position]::new($x, $y)))
                                {
                                    [System.ConsoleColor]::Blue
                                }
                                else
                                {
                                    If ($Grid[$x, $y].IsWhiteTile)
                                    {
                                        [System.ConsoleColor]::DarkYellow
                                    }
                                    else
                                    {
                                        [System.ConsoleColor]::DarkRed
                                    }
                                } )
                                [System.ConsoleColor]$pieceColour = $( If ($Grid[$x, $y].OccupantAllegiance -eq [Allegiance]::White)
                                {
                                    [System.ConsoleColor]::White
                                }
                                else
                                {
                                    [System.ConsoleColor]::Black
                                } )
                                $output = $Grid[$x, $y].GetIcon() + " "
                                Write-Host $output -NoNewLine -BackgroundColor $colour -ForegroundColor $pieceColour

                            }
                            Write-Host " "

                        }
                    }
                    else
                    {
                        if ($Grid[$currentPosition.X, $currentPosition.Y].MovePiece($currentPosition, $selectedTarget, $Grid, $moveCache,$false))
                        {
                            $whitesTurn = -not $whitesTurn;
                            break;
                        }
                        else
                        {
                            echo "Invalid Move";
                        }
                    }
                }
                else
                {
                    echo "Syntax Error. Use Format Ka1b2";
                }
            }
        }
    }
    else #AI Turn
    {
        #selectedPosition
        [Position]$AIselectedTarget = [Position]::new(0, 0)
        #Current Position
        [Position]$AIcurrentPosition = [Position]::new(0, 0)
        $moveCache.GetAIMove([ref]$AIcurrentPosition,[ref]$AIselectedTarget)
        Write-Host "AI MOVE FROM $($AIcurrentPosition.X),$($AIcurrentPosition.Y) to $($AIselectedTarget.X),$($AIselectedTarget.Y)"
        $Grid[$AIcurrentPosition.X, $AIcurrentPosition.Y].MovePiece($AIcurrentPosition, $AIselectedTarget, $Grid, $moveCache,$false)
        $whitesTurn = -not $whitesTurn;
    }
}