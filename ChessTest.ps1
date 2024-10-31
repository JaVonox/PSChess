param($boardType)

#Game constructs
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
    [Position]$MoveTo
    [float]$ScoreChange
    [Position]$TargetRemovePosition
    [bool]$MovesTarget
    [Position]$NewTargetPosition

    MoveVsScore()
    {
        
    }

    MoveVsScore([Position]$nPos,[float]$nScoreChange,[Position]$nTargetRemovePos,[bool]$newMovesTarget,[Position]$newMovePos)
    {
        $this.MoveTo = $nPos
        $this.ScoreChange = $nScoreChange
        $this.TargetRemovePosition = $nTargetRemovePos
        $this.MovesTarget = $newMovesTarget
        $this.NewTargetPosition = $newMovePos
    }

}

class IMoveRule {
    [System.Collections.Generic.List[MoveVsScore]] GetPossibleMoves([Position]$from, [Allegiance]$allegiance, $board,[int]$SelectedTurn) {
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

    [System.Collections.Generic.List[MoveVsScore]] GetPossibleMoves([Position]$from,[Allegiance]$myAllegiance,$board,[int]$SelectedTurn)
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
                    $moves.Add([MoveVsScore]::new($pos,$($board[$x,$y].GetTakingScore($myAllegiance)),$pos,$false,$pos))
                }
                break;
            }
            
            $moves.Add([MoveVsScore]::new($pos,0,$pos,$false,$pos))
            
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

    [System.Collections.Generic.List[MoveVsScore]] GetPossibleMoves([Position]$from, [Allegiance]$allegiance, $board,[int]$SelectedTurn) {
        if(& $this.Condition $from $allegiance $board $SelectedTurn) #& operator executes $this.Condition as a script using the parameters given
        {
            return & $this.MoveGenerator $from $allegiance $board $SelectedTurn
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

    [System.Collections.Generic.List[MoveVsScore]] GetPossibleMoves([Position]$from, [Allegiance]$allegiance, $board,[int]$SelectedTurn) {
        $allMoves = [System.Collections.Generic.List[MoveVsScore]]::new()
        foreach($rule in $this.Rules)
        {
            $moves = $rule.GetPossibleMoves($from,$allegiance,$board,$SelectedTurn)
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
    [float]$ScoreChangeIfApplied

    PostMoveEffect()
    {

    }

    PostMoveEffect([scriptBlock]$nCondition,[scriptBlock]$nEffect,[float]$nScoreChange)
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
    [float] UpdateCache([Allegiance]$PlayerAllegiance,$Tiles,[int]$DoChecks,[ref]$MoveCounter,[int]$SelectedTurn)
    {
        $this.SearchDepth = $DoChecks
        
        [System.Collections.Generic.List[string]]$BestMoves = [System.Collections.Generic.List[string]]::new()
        [float]$BestMoveScore = [float]::MinValue
        [float]$CumulativeScore = 0
        [Position] $KingPosition = $null
        
        $this.cachedMoves.Clear()
        $this.AIMove = ""

        For ($y = 0; $y -le 7 -and $KingPosition -eq $null; $y++) {
            For ($x = 0; $x -le 7; $x++) {
                if ($PlayerAllegiance -eq $Tiles[$x, $y].OccupantAllegiance -and $Tiles[$x,$y].OccupantPiece -eq [King])
                {
                    $KingPosition = [Position]::new($x,$y)
                    break;
                }
            }
        }

        For ($y = 0; $y -le 7; $y++) {
            For ($x = 0; $x -le 7; $x++) {
                if ($PlayerAllegiance -eq $Tiles[$x, $y].OccupantAllegiance)
                {
                    $CurrentPosition = [Position]::new($x, $y)
                    [System.Collections.Generic.List[MoveVsScore]]$moves = $Tiles[$x, $y].GetMoves($CurrentPosition, $PlayerAllegiance, $Tiles,$SelectedTurn)

                    foreach ($moveTarget in $moves)
                    {
                        
                        $MoveCounter.Value = $MoveCounter.Value + 1
                        [float]$moveScore = [float]($moveTarget.ScoreChange)
                        $moveScore += $($Tiles[$x,$y].OccupantPiece::PostMove.AddScoreToMove($moveTarget.MoveTo,$PlayerAllegiance,$Tiles))
                        $moveKey = $this.GetMoveKey($CurrentPosition, $moveTarget.MoveTo)
                        
                        #TODO is it possible to break this by having a king move cause a possible >-900 lookahead score if it would sacrifice the king?
                        #If we have another search depth to go, append a depth score
                        if ($this.SearchDepth -gt 0)
                        {
                            $moveScore += $this.GetDepthScore($CurrentPosition, $moveTarget.MoveTo, $Tiles, $this, $PlayerAllegiance,$KingPosition, $MoveCounter,$SelectedTurn)
                        }
                        
                        # Now check if this move would lose our king AFTER all scoring is done
                        if($moveScore -lt -600) 
                        {
                            continue  # Skip this move as it loses our king
                        }

                        $moveTarget.ScoreChange = $moveScore
                        $this.cachedMoves[$moveKey] = $moveTarget
                        
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
        
        return [float]::MinValue
    }

    #Simulates going one layer deeper into the moves, and checking what the possible results of all player moves would be
    [float] GetDepthScore([Position]$FromPos,[Position]$ToPos,$Tiles,$MoveCache,[Allegiance]$PlayerAllegiance,[Position]$MyKingPos,[ref]$MoveCounter,[int]$SelectedTurn)
    {
        # Create deep copy of board
        $TilesInstance = New-Object 'Tile[,]' 8,8
        for ($y = 0; $y -lt 8; $y++) {
            for ($x = 0; $x -lt 8; $x++) {
                $TilesInstance[$x,$y] = $Tiles[$x,$y].Clone()
            }
        }

        $moveResult = $TilesInstance[$FromPos.X, $FromPos.Y].MovePiece($FromPos, $ToPos, $TilesInstance, $this,$true,$SelectedTurn)

        if (-not $moveResult) {
            Write-Host "Invalid move, returning 0"
            return 0
        }

        # Find king's actual position after the move
        [Position]$ActualKingPos = $null
        For ($y = 0; $y -le 7; $y++) {
            For ($x = 0; $x -le 7; $x++) {
                if ($PlayerAllegiance -eq $TilesInstance[$x, $y].OccupantAllegiance -and
                        $TilesInstance[$x,$y].OccupantPiece -eq [King])
                {
                    $ActualKingPos = [Position]::new($x,$y)
                    break
                }
            }
            if ($ActualKingPos -ne $null) { break }
        }

        # Check if our king is in check after this move
        if($this.IsKingInCheck($PlayerAllegiance, $ActualKingPos, $TilesInstance))
        {
            return -900
        }

        $CacheInstance = [MoveCache]::new()
        $OpponentAllegiance = $(If($PlayerAllegiance -eq [Allegiance]::White) {[Allegiance]::Black} else {[Allegiance]::White})
        [int]$NewDepth = $this.SearchDepth - 1
        [int]$NewTurn = $SelectedTurn + 1
        [float]$depthScore = [math]::floor($CacheInstance.UpdateCache($OpponentAllegiance, $TilesInstance, $NewDepth,$MoveCounter,$NewTurn))
        
        return -$depthScore
    }

    [bool] GetReplacePosition([Position]$FromPos,[Position]$ToPos,[ref]$RemovePosition,[ref]$ShouldReplace,[ref]$ReplacePosition)
    {
        $moveKey = $this.GetMoveKey($FromPos, $ToPos)
        if ($this.cachedMoves.ContainsKey($moveKey))
        {
            $RemovePosition.Value = $this.cachedMoves[$moveKey].TargetRemovePosition
            $ShouldReplace.Value = $this.cachedMoves[$moveKey].MovesTarget
            $ReplacePosition.Value = $this.cachedMoves[$moveKey].NewTargetPosition
            return $true
        }
        return $false
    }

    hidden [bool] IsKingInCheck([Allegiance]$kingAllegiance, [Position]$kingPos, [Tile[,]]$board) {
        $opponentAllegiance = $(If($kingAllegiance -eq [Allegiance]::White) {[Allegiance]::Black} else {[Allegiance]::White})

        # Check diagonal rays (Bishop/Queen)
        $diagonalRays = @(
            @(1,1), @(1,-1), @(-1,1), @(-1,-1)
        )
        foreach ($ray in $diagonalRays) {
            $x = $kingPos.X
            $y = $kingPos.Y

            while ($true) {
                $x += $ray[0]
                $y += $ray[1]

                if ($x -lt 0 -or $x -gt 7 -or $y -lt 0 -or $y -gt 7) { break }

                $piece = $board[$x,$y].OccupantPiece
                $allegiance = $board[$x,$y].OccupantAllegiance

                if ($allegiance -ne [Allegiance]::None) {
                    if ($allegiance -eq $opponentAllegiance -and
                            ($piece -eq [Queen] -or $piece -eq [Bishop])) {
                        return $true
                    }
                    break  # Ray is blocked
                }
            }
        }

        # Check straight rays (Rook/Queen)
        $straightRays = @(
            @(0,1), @(0,-1), @(1,0), @(-1,0)
        )
        foreach ($ray in $straightRays) {
            $x = $kingPos.X
            $y = $kingPos.Y

            while ($true) {
                $x += $ray[0]
                $y += $ray[1]

                if ($x -lt 0 -or $x -gt 7 -or $y -lt 0 -or $y -gt 7) { break }

                $piece = $board[$x,$y].OccupantPiece
                $allegiance = $board[$x,$y].OccupantAllegiance

                if ($allegiance -ne [Allegiance]::None) {
                    if ($allegiance -eq $opponentAllegiance -and
                            ($piece -eq [Queen] -or $piece -eq [Rook])) {
                        return $true
                    }
                    break  # Ray is blocked
                }
            }
        }

        # Check knight positions
        $knightMoves = @(
            @(-2,-1), @(-2,1), @(-1,-2), @(-1,2),
            @(1,-2), @(1,2), @(2,-1), @(2,1)
        )
        foreach ($move in $knightMoves) {
            $x = $kingPos.X + $move[0]
            $y = $kingPos.Y + $move[1]

            if ($x -ge 0 -and $x -le 7 -and $y -ge 0 -and $y -le 7) {
                $piece = $board[$x,$y].OccupantPiece
                $allegiance = $board[$x,$y].OccupantAllegiance

                if ($allegiance -eq $opponentAllegiance -and $piece -eq [Knight]) {
                    return $true
                }
            }
        }

        # Check pawn attacks
        $pawnDirection = $(If($kingAllegiance -eq [Allegiance]::White) {1} else {-1})
        $pawnAttacks = @(
            @(-1, -$pawnDirection),
            @(1, -$pawnDirection)
        )
        foreach ($attack in $pawnAttacks) {
            $x = $kingPos.X + $attack[0]
            $y = $kingPos.Y + $attack[1]

            if ($x -ge 0 -and $x -le 7 -and $y -ge 0 -and $y -le 7) {
                $piece = $board[$x,$y].OccupantPiece
                $allegiance = $board[$x,$y].OccupantAllegiance

                if ($allegiance -eq $opponentAllegiance -and $piece -eq [Pawn]) {
                    return $true
                }
            }
        }

        return $false
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
        param($from, $allegiance, $board,[int]$SelectedTurn) $true
    },
    {
        param($from, $allegiance, $board,[int]$SelectedTurn)
        $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
        if ($board[$from.X, $($from.Y + $MovementDirection)].OccupantAllegiance -eq [Allegiance]::None)
        {
            $moves = [System.Collections.Generic.List[MoveVsScore]]::new()
            
            $firstMove = [Position]::new($from.X, $($from.Y + $MovementDirection))
            $moves.Add([MoveVsScore]::new($firstMove,0.5,$firstMove,$false,$firstMove))
            
            if(($allegiance -eq [Allegiance]::White -and $from.Y -eq 6) -or ($allegiance -eq [Allegiance]::Black -and $from.Y -eq 1))
            {
                if ($board[$from.X, $($from.Y + $($MovementDirection * 2))].OccupantAllegiance -eq [Allegiance]::None)
                {
                    $secondMove = [Position]::new($from.X, $($from.Y + $MovementDirection * 2))
                    $moves.Add([MoveVsScore]::new($secondMove,0.5,$secondMove,$false,$secondMove))
                }
            }
            return $moves
        }
        return [System.Collections.Generic.List[MoveVsScore]]::new()
    }),[SpecialRule]::new( #Check right diagonal
        { 
            param($from, $allegiance, $board,[int]$SelectedTurn)
            $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
            $OppositeAllegiance = $(If($allegiance -eq [Allegiance]::White) {[Allegiance]::Black} Else {[Allegiance]::White})
            $x = $from.X + 1 
            $y = $from.Y + $MovementDirection
            return $x -ge 0 -and $x -lt 8 -and $y -ge 0 -and $y -lt 8 -and $board[$x,$y].OccupantAllegiance -eq $OppositeAllegiance
        },
        {
            param($from, $allegiance, $board,[int]$SelectedTurn)
            $moves = [System.Collections.Generic.List[MoveVsScore]]::new()
            $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
            $newPos = [Position]::new($($from.X + 1), $($from.Y + $MovementDirection))
            [int]$rScore = $board[$newPos.X, $newPos.Y].GetTakingScore($allegiance)
            $moves.Add([MoveVsScore]::new($newPos, $rScore,$newPos,$false,$newPos))
            return $moves
        })
        ,[SpecialRule]::new( #Check left diagonal
        {
            param($from, $allegiance, $board,[int]$SelectedTurn)
            $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
            $OppositeAllegiance = $(If($allegiance -eq [Allegiance]::White) {[Allegiance]::Black} Else {[Allegiance]::White})
            $x = $from.X - 1
            $y = $from.Y + $MovementDirection
            return $x -ge 0 -and $x -lt 8 -and $y -ge 0 -and $y -lt 8 -and $board[$x,$y].OccupantAllegiance -eq $OppositeAllegiance
        },
        {
            param($from, $allegiance, $board,[int]$SelectedTurn)
            $moves = [System.Collections.Generic.List[MoveVsScore]]::new()
            $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
            $newPos = [Position]::new($($from.X - 1), $($from.Y + $MovementDirection))
            [int]$lScore = $board[$newPos.X, $newPos.Y].GetTakingScore($allegiance)
            $moves.Add([MoveVsScore]::new($newPos, $lScore,$newPos,$false,$newPos))
            return $moves
        })
        ,[SpecialRule]::new( #Check en passant left
        {
            param($from, $allegiance, $board,[int]$SelectedTurn)
            $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
            $FromYPositionRequirement = $(If($allegiance -eq [Allegiance]::White) {3} Else {4}) #If our pawn is white, we can only en passant from row 4 - if our pawn is black, we can only en passant from row 5
            if($from.Y -ne $FromYPositionRequirement){return $false}
            $OppositeAllegiance = $(If($allegiance -eq [Allegiance]::White) {[Allegiance]::Black} Else {[Allegiance]::White})
            $x = $from.X - 1
            $IsEnemyPawn = $board[$x,$FromYPositionRequirement].OccupantAllegiance -eq $OppositeAllegiance -and $board[$x,$FromYPositionRequirement].OccupantPiece -eq [Pawn]
            $IsCorrectTurn = $($board[$x,$FromYPositionRequirement].OccupantLastMovedTurn -eq $($SelectedTurn-1))
            return $x -lt 8 -and $from.Y -eq $FromYPositionRequirement -and $IsEnemyPawn -and $IsCorrectTurn -and $board[$x,$($from.Y + $MovementDirection)].OccupantAllegiance -eq [Allegiance]::None
        },
        {
            param($from, $allegiance, $board,[int]$SelectedTurn)
            $moves = [System.Collections.Generic.List[MoveVsScore]]::new()
            $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
            $newPos = [Position]::new($($from.X - 1), $($from.Y + $MovementDirection))
            $enemyDeathPos = [Position]::new($($newPos.X), $($newPos.Y - $MovementDirection))
            [int]$lScore = $board[$enemyDeathPos.X, $enemyDeathPos.Y].GetTakingScore($allegiance) + 0.5
            $moves.Add([MoveVsScore]::new($newPos, $lScore,$enemyDeathPos,$false,$newPos))
            return $moves
        })
        ,[SpecialRule]::new( #Check en passant right
        {
            param($from, $allegiance, $board,[int]$SelectedTurn)
            $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
            $FromYPositionRequirement = $(If($allegiance -eq [Allegiance]::White) {3} Else {4}) #If our pawn is white, we can only en passant from row 4 - if our pawn is black, we can only en passant from row 5
            if($from.Y -ne $FromYPositionRequirement){return $false}
            $OppositeAllegiance = $(If($allegiance -eq [Allegiance]::White) {[Allegiance]::Black} Else {[Allegiance]::White})
            $x = $from.X + 1
            $IsEnemyPawn = $board[$x,$FromYPositionRequirement].OccupantAllegiance -eq $OppositeAllegiance -and $board[$x,$FromYPositionRequirement].OccupantPiece -eq [Pawn]
            $IsCorrectTurn = $($board[$x,$FromYPositionRequirement].OccupantLastMovedTurn -eq $($SelectedTurn-1))
            return $x -lt 8 -and $from.Y -eq $FromYPositionRequirement -and $IsEnemyPawn -and $IsCorrectTurn -and $board[$x,$($from.Y + $MovementDirection)].OccupantAllegiance -eq [Allegiance]::None
        },
        {
            param($from, $allegiance, $board,[int]$SelectedTurn)
            $moves = [System.Collections.Generic.List[MoveVsScore]]::new()
            $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
            $newPos = [Position]::new($($from.X + 1), $($from.Y + $MovementDirection))
            $enemyDeathPos = [Position]::new($($newPos.X), $($newPos.Y - $MovementDirection))
            [int]$rScore = $board[$enemyDeathPos.X, $enemyDeathPos.Y].GetTakingScore($allegiance) + 0.5
            $moves.Add([MoveVsScore]::new($newPos, $rScore,$enemyDeathPos,$false,$newPos))
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
    
}

class Rook : PieceTypeBase
{
    static [char]$pieceIcon = '♖';
    static [int]$pieceValue = 5;
    static [CompositeRule]$PieceRules = [CompositeRule]::new(@([DirectionalRule]::new(1,0,$true),[DirectionalRule]::new(-1,0,$true),
    [DirectionalRule]::new(0,1,$true),[DirectionalRule]::new(0,-1,$true)));
    static [PostMoveEffect]$PostMove = [PostMoveEffect]::new({param($newPosition, $allegiance, $board)return $false},{param($newPosition, $allegiance, $board)},0)
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
        ,[SpecialRule]::new( #Castle Left #TODO spaces inbetween cannot be an attackable position, king is not currently in check
        {
            param($from, $allegiance, $board,[int]$SelectedTurn)
            if($board[$from.X,$from.Y].OccupantLastMovedTurn -eq 0)
            {
                [bool]$FreeTiles = $($board[$($from.X-1),$from.Y].OccupantAllegiance -eq [Allegiance]::None -and $board[$($from.X-2),$from.Y].OccupantAllegiance -eq [Allegiance]::None -and $board[$($from.X-3),$from.Y].OccupantAllegiance -eq [Allegiance]::None)
                [bool]$RookExists = $($board[$($from.X-4),$from.Y].OccupantPiece -eq [Rook] -and $board[$($from.X-4),$from.Y].OccupantAllegiance -eq $allegiance -and $board[$($from.X-4),$from.Y].OccupantLastMovedTurn -eq 0 )
                return $FreeTiles -and $RookExists
            }
            return $false
        },
        {
            param($from, $allegiance, $board,[int]$SelectedTurn)
            $moves = [System.Collections.Generic.List[MoveVsScore]]::new()
            $newPos = [Position]::new($($from.X - 2), $($from.Y))
            $removedRookPos = [Position]::new($($newPos.X - 2), $($newPos.Y))
            $addedRookPos = [Position]::new($($newPos.X + 1), $($newPos.Y))
            $moves.Add([MoveVsScore]::new($newPos, 0.5,$removedRookPos,$true,$addedRookPos))
            return $moves
        })
        ,[SpecialRule]::new( #Castle Right #TODO spaces inbetween cannot be an attackable position, king is not currently in check
        {
            param($from, $allegiance, $board,[int]$SelectedTurn)
            if($board[$from.X,$from.Y].OccupantLastMovedTurn -eq 0)
            {
                [bool]$FreeTiles = $($board[$($from.X+1),$from.Y].OccupantAllegiance -eq [Allegiance]::None -and $board[$($from.X+2),$from.Y].OccupantAllegiance -eq [Allegiance]::None)
                [bool]$RookExists = $($board[$($from.X+3),$from.Y].OccupantPiece -eq [Rook] -and $board[$($from.X+3),$from.Y].OccupantAllegiance -eq $allegiance -and $board[$($from.X+3),$from.Y].OccupantLastMovedTurn -eq 0 )
                return $FreeTiles -and $RookExists
            }
            return $false
        },
        {
            param($from, $allegiance, $board,[int]$SelectedTurn)
            $moves = [System.Collections.Generic.List[MoveVsScore]]::new()
            $newPos = [Position]::new($($from.X + 2), $($from.Y))
            $removedRookPos = [Position]::new($($newPos.X + 1), $($newPos.Y))
            $addedRookPos = [Position]::new($($newPos.X - 1), $($newPos.Y))
            $moves.Add([MoveVsScore]::new($newPos, 0.5,$removedRookPos,$true,$addedRookPos))
            return $moves
        })
    ))
    static [PostMoveEffect]$PostMove = [PostMoveEffect]::new({param($newPosition, $allegiance, $board)return $false},{param($newPosition, $allegiance, $board)},0)
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
    [int]$OccupantLastMovedTurn;
    [bool]$IsWhiteTile;

    Tile($NewOccupantType,$NewOccupantAllegiance,$NewBackIsWhite)
    {
        $this.OccupantPiece = $NewOccupantType;
        $this.OccupantAllegiance = $NewOccupantAllegiance;
        $this.OccupantLastMovedTurn = 0
        $this.IsWhiteTile = $NewBackIsWhite;
    }

    [bool] CheckCanMoveTo([Position]$FromPos,[Position]$ToPos,$Tiles,$MoveCache)
    {
        return $this.OccupantAllegiance -ne [Allegiance]::None -and $MoveCache.IsValidMove($FromPos,$ToPos);
    }

    [System.Collections.Generic.List[MoveVsScore]] GetMoves([Position]$from, [Allegiance]$allegiance, $board,[int]$SelectedTurn)
    {
        return $this.OccupantPiece::PieceRules.GetPossibleMoves($from, $allegiance, $board,$SelectedTurn)
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

    [bool] MovePiece([Position]$FromPos,[Position]$ToPos,$Tiles,$MoveCache,$IgnoreCheck,[int]$SelectedTurn)
    {
        if($IgnoreCheck -or $this.CheckCanMoveTo($FromPos,$ToPos,$Tiles,$MoveCache))
        {
            [Position] $RemovePosition = [Position]::new(0,0)
            [bool] $ShouldReplace = $false
            [Position] $ReplacePosition = [Position]::new(0,0)
            
            #If this move causes a replacement - i.e any move that effects more than one tile, such as en passant or castling
            if ($MoveCache.GetReplacePosition($FromPos,$ToPos,[ref]$RemovePosition,[ref]$ShouldReplace,[ref]$ReplacePosition)) {
                
                if($ShouldReplace)
                {
                    $Tiles[$ReplacePosition.X, $ReplacePosition.Y].OccupantPiece = $Tiles[$RemovePosition.X, $RemovePosition.Y].OccupantPiece
                    $Tiles[$ReplacePosition.X, $ReplacePosition.Y].OccupantAllegiance = $Tiles[$RemovePosition.X, $RemovePosition.Y].OccupantAllegiance
                    $Tiles[$ReplacePosition.X, $ReplacePosition.Y].OccupantLastMovedTurn = $SelectedTurn
                }
                
                $Tiles[$RemovePosition.X, $RemovePosition.Y].OccupantPiece = $null
                $Tiles[$RemovePosition.X, $RemovePosition.Y].OccupantAllegiance = [Allegiance]::None
                $Tiles[$RemovePosition.X, $RemovePosition.Y].OccupantLastMovedTurn = 0
            }
            
            #Swap Pieces
            $Tiles[$ToPos.X,$ToPos.Y].OccupantPiece = $this.OccupantPiece;
            $this.OccupantPiece = $null;
            
            $newAllegiance = $this.OccupantAllegiance;
            $Tiles[$ToPos.X,$ToPos.Y].OccupantAllegiance = $newAllegiance;
            $this.OccupantAllegiance = [Allegiance]::None;
            
            $Tiles[$ToPos.X,$ToPos.Y].OccupantLastMovedTurn = $SelectedTurn;
            $this.OccupantLastMovedTurn = 0;
            
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

function GenerateBaseGrid($Tiles,[scriptBlock]$Pattern)
{
    $IndexTyping = @([Rook],[Knight],[Bishop],[Queen],[King],[Pawn]);
    for ($y = 1; $y -le 8; $y++) {
        $IsWhiteBarracks = ($y -ge 7);
        for ($x = 1; $x -le 8; $x++) {
            $TileOccupantIndex = & $Pattern $x $y

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

function DrawGrid([Tile[,]]$Tiles,[ref]$moveCache,[Position]$queryPosition)
{
    Write-Host $(If($whitesTurn) {"Your Turn (Turn $currentTurn)"} Else {"Enemy Thinking (Turn $currentTurn)..."});
    
    [bool]$IsMoveQuery = $($queryPosition -ne $null)
    
    Write-Host " a b c d e f g h ";

    For ($y = 0; $y -le 7;$y++)
    {
        Write-Host $([Math]::Abs($y-8)) -NoNewLine
        For ($x = 0; $x -le 7;$x++)
        {
            $output = $Tiles[$x,$y].GetIcon() + " "

            [System.ConsoleColor]$colour = [System.ConsoleColor]::White
            if($IsMoveQuery -and $moveCache.Value.IsValidMove($queryPosition,[Position]::new($x, $y)))
            {
                $colour = [System.ConsoleColor]::Cyan
            }
            else
            {
                $colour = $(If($Tiles[$x,$y].IsWhiteTile){[System.ConsoleColor]::DarkYellow}else{[System.ConsoleColor]::DarkRed})
            }
            
            [System.ConsoleColor]$pieceColour = $(If($Tiles[$x,$y].OccupantAllegiance -eq [Allegiance]::White){[System.ConsoleColor]::White}else{[System.ConsoleColor]::Black})
            Write-Host $output -NoNewLine -BackgroundColor $colour -ForegroundColor $pieceColour
        }
        Write-Host " "
    }
}


[Tile[,]]$Grid = New-Object 'Tile[,]' 8,8

[scriptBlock]$NewPattern

switch($boardType)
{
    {$null -eq $_ -or $_ -eq ''} { $NewPattern = {param($x,$y) return [int]($y -eq 1 -or $y -eq 8) * $(If($x -le 5) {$x} Else {8-$x+1}) + ([int]($y -eq 2 -or $y -eq 7) * 6) - 1};break; }
    "C1" {$NewPattern = {param($x,$y) return ([int]($y -eq 1 -and $x -eq 8) * 5 + [int]($y -eq 7 -and $x -eq 2) * 5 + [int]($y -eq 1 -and $x -eq 1) * 1 + [int]($y -eq 1 -and $x -eq 3) * 1 + [int]($y -eq 2 -and $x -eq 7) * 4) - 1}; break; }
    "C2" { $NewPattern = {param($x,$y) return ([int]($y -eq 1 -and $x -eq 5) * 5 + [int]($y -eq 7 -and $x -eq 8) * 5 + [int]($y -eq 2 -and $x -eq 6) * 2 + [int]($y -eq 2 -and $x -eq 8) * 4 + [int]($y -eq 7 -and ($x -eq 6 -or $x -eq 7)) * 6) - 1}; break; }
}

GenerateBaseGrid $Grid $NewPattern
$moveCache = [MoveCache]::new()

$continue = $true
$whitesTurn = $true
$AiEnabled = $true
$currentTurn = 0
while($continue)
{
    $currentTurn++
    #Clear-Host
    $AIDepth = $(If($whitesTurn -or (-not $AiEnabled)) {1} Else {2});

    Write-Host $(If($whitesTurn) {"Your Turn (Turn $currentTurn)"} Else {"Enemy Thinking (Turn $currentTurn)..."});
    
    $totalMoves = 0
    $maxScore = $moveCache.UpdateCache($(If($whitesTurn){[Allegiance]::White}else{[Allegiance]::Black}),$Grid,$AIDepth,[ref]$totalMoves,$currentTurn)
    Write-Host "Analysed $totalMoves Moves maxScore $maxScore"
    
    DrawGrid $Grid ([ref]$moveCache) $null

    if($maxScore -eq [float]::MinValue) #If there is no moves left
    {
        $winner = $(If($whitesTurn){"Black"}else{"White"})
        Write-Host "Checkmate. $winner Wins!"
        break;
    }
    
    if($whitesTurn -or (-not $AiEnabled))
    {
        while ($true)
        {
            Write-Host " "
            $Move = Read-Host "Enter Move";

            if ($Move -eq "AI")
            {
                Write-Host "AI TOGGLED"
                $AiEnabled = -not $AiEnabled
            }

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
                        #Clear-Host
                        Write-Host $(If($whitesTurn) {"Your Turn ($currentTurn)"} Else {"Enemy Thinking ($currentTurn)..."});

                        DrawGrid $Grid ([ref]$moveCache) $currentPosition
                        Write-Host "Piece: $($Grid[$currentPosition.X,$currentPosition.Y].OccupantAllegiance) $($Grid[$currentPosition.X,$currentPosition.Y].OccupantPiece) (Last Moved Turn: $($Grid[$currentPosition.X,$currentPosition.Y].OccupantLastMovedTurn))"
                    }
                    else
                    {
                        if ($Grid[$currentPosition.X, $currentPosition.Y].MovePiece($currentPosition, $selectedTarget, $Grid, $moveCache,$false,$currentTurn))
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
        #TODO rarely the AI will not move
        #selectedPosition
        [Position]$AIselectedTarget = [Position]::new(0, 0)
        #Current Position
        [Position]$AIcurrentPosition = [Position]::new(0, 0)
        $moveCache.GetAIMove([ref]$AIcurrentPosition,[ref]$AIselectedTarget)
        Write-Host "AI MOVE $($Grid[$AIcurrentPosition.X,$AIcurrentPosition.Y].OccupantPiece) FROM $($AIcurrentPosition.X),$($AIcurrentPosition.Y) to $($AIselectedTarget.X),$($AIselectedTarget.Y)"
        if (-not $Grid[$AIcurrentPosition.X, $AIcurrentPosition.Y].MovePiece($AIcurrentPosition, $AIselectedTarget, $Grid, $moveCache,$false,$currentTurn))
        {
            Write-Host "BAD MOVE" Background-Color [System.ConsoleColor]::DarkRef
            break
        }
        $whitesTurn = -not $whitesTurn;
    }
}