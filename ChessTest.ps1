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

class IMoveRule {
    [System.Collections.Generic.List[Position]] GetPossibleMoves([Position]$from, [Allegiance]$allegiance, $board) {
        throw "Must be implemented"
    }
}

#Movement Rules

#Rules for checking a specific direction
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

    [System.Collections.Generic.List[Position]] GetPossibleMoves([Position]$from,[Allegiance]$myAllegiance,$board)
    {
        $moves = [System.Collections.Generic.List[Position]]::new();
        $x = $from.x + $this.DirX;
        $y = $from.y + $this.DirY;
        
        while($x -ge 0 -and $x -lt 8 -and $y -ge 0 -and $y -lt 8)
        {
            $pos = [Position]::new($x,$y);
            if($board[$x,$y].OccupantAllegiance -ne [Allegiance]::None) #If there is an occupant on this tile
            {
                if($board[$x,$y].OccupantAllegiance -ne $myAllegiance)
                {
                    $moves.Add($pos)
                }
                break;
            }
            
            $moves.Add($pos)
            
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

    [System.Collections.Generic.List[Position]] GetPossibleMoves([Position]$from, [string]$allegiance, $board) {
        if(& $this.Condition $from $allegiance $board) #& operator executes $this.Condition as a script using the parameters given
        {
            return & $this.MoveGenerator $from $allegiance $board
        }
        return [System.Collections.Generic.List[Position]]::new();
    }
}

class CompositeRule : IMoveRule
{
    [IMoveRule[]]$Rules
    
    CompositeRule([IMoveRule[]]$ComponentRules)
    {
        $this.Rules = $ComponentRules
    }

    [System.Collections.Generic.List[Position]] GetPossibleMoves([Position]$from, [string]$allegiance, $board) {
        $allMoves = [System.Collections.Generic.List[Position]]::new()
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

class MoveCache
{
    [hashtable]$cachedMoves = @{}

    hidden [string] GetMoveKey([Position]$from, [Position]$to) {
        return ($from.X) -bor ($from.Y -shl 3) -bor ($to.X -shl 6) -bor ($to.Y -shl 9)
    }
    
    [void] UpdateCache([Allegiance]$PlayerAllegiance,$Tiles)
    {
        $this.cachedMoves.Clear()
        For ($y = 0; $y -le 7;$y++)
        {
            For ($x = 0; $x -le 7;$x++)
            {
                if($PlayerAllegiance -ne $Tiles[$x,$y].OccupantAllegiance) {continue}
                $CurrentPosition = [Position]::new($x,$y);
                [System.Collections.Generic.List[Position]]$moves = $Tiles[$x,$y].GetMoves($CurrentPosition,$PlayerAllegiance,$Tiles)
                foreach ($moveTarget in $moves)
                {
                    $this.cachedMoves[$this.GetMoveKey($CurrentPosition,$moveTarget)] = $true
                }
            }
        }
    }
    
    [bool] IsValidMove([Position]$FromPosition,[Position]$TargetPosition)
    {
        $moveKey = $this.GetMoveKey($FromPosition, $TargetPosition)
        return $this.cachedMoves.ContainsKey($moveKey)
    }
}
#Pieces

class PieceTypeBase
{
    static [char]$pieceIcon = 'N';
    static [CompositeRule]$PieceRules = @{}
}

class Pawn : PieceTypeBase
{
    static [char]$pieceIcon = '♙';
    static [CompositeRule]$PieceRules = [CompositeRule]::new(@([SpecialRule]::new(
    {
        #pawn moves away from its own side and can move twice on first turn
        param($from, $allegiance, $Tiles) $true
    },
    {
        param($from, $allegiance, $Tiles)
        $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
        if ($board[$from.X, $($from.Y + $MovementDirection)].OccupantAllegiance -eq [Allegiance]::None)
        {
            $moves = [System.Collections.Generic.List[Position]]::new()
            $moves.Add([Position]::new($from.X, $($from.Y + $MovementDirection)))
            if(($allegiance -eq [Allegiance]::White -and $from.Y -eq 6) -or ($allegiance -eq [Allegiance]::Black -and $from.Y -eq 2))
            {
                if ($board[$from.X, $($from.Y + $($MovementDirection * 2))].OccupantAllegiance -eq [Allegiance]::None)
                {
                    $moves.Add([Position]::new($from.X, $($from.Y + ($MovementDirection * 2))))
                }
            }
            return $moves
        }
        return [System.Collections.Generic.List[Position]]::new()
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
    $moves = [System.Collections.Generic.List[Position]]::new()
    $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
    $moves.Add([Position]::new($from.X + 1, $from.Y + $MovementDirection))
    return $moves
    }),[SpecialRule]::new( #Check left diagonal
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
                $moves = [System.Collections.Generic.HashSet[Position]]::new()
                $MovementDirection = $(If($allegiance -eq [Allegiance]::White) {-1} Else {1})
                $moves.Add([Position]::new($from.X - 1, $from.Y + $MovementDirection))
                return $moves
            })
    ))
    
    #TODO ADD EN PASSANT
}

class Rook : PieceTypeBase
{
    static [char]$pieceIcon = '♖';
    static [CompositeRule]$PieceRules = [CompositeRule]::new(@([DirectionalRule]::new(1,0,$true),[DirectionalRule]::new(-1,0,$true),
    [DirectionalRule]::new(0,1,$true),[DirectionalRule]::new(0,-1,$true)));
    
    #TODO ADD CASTLING
}

class Knight : PieceTypeBase
{
    static [char]$pieceIcon = '♘';
    static [CompositeRule]$PieceRules = [CompositeRule]::new(@([DirectionalRule]::new(2,1,$false),[DirectionalRule]::new(2,-1,$false),
    [DirectionalRule]::new(-2,1,$false),[DirectionalRule]::new(-2,-1,$false),
            [DirectionalRule]::new(1,2,$false),[DirectionalRule]::new(1,-2,$false),
            [DirectionalRule]::new(-1,2,$false),[DirectionalRule]::new(-2,-2,$false)));
}

class Bishop : PieceTypeBase
{
    static [char]$pieceIcon = '♗';
    static [CompositeRule]$PieceRules = [CompositeRule]::new(@([DirectionalRule]::new(1,1,$true),[DirectionalRule]::new(1,-1,$true),
    [DirectionalRule]::new(-1,1,$true),[DirectionalRule]::new(-1,-1,$true)));
}

class King : PieceTypeBase
{
    static [char]$pieceIcon = '♔';
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

    #TODO ADD RULE PREVENTING PUTTING SELF IN CHECK
    #TODO ADD CASTLING?
}

class Queen : PieceTypeBase
{
    static [char]$pieceIcon = '♕';
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
}

class Tile
{
    [System.Type]$OccupantPiece
    [Allegiance]$OccupantAllegiance;
    [char]$BackChar;

    Tile($NewOccupantType,$NewOccupantAllegiance,$NewBackIsWhite)
    {
        $this.OccupantPiece = $NewOccupantType;
        $this.OccupantAllegiance = $NewOccupantAllegiance;
        $this.BackChar = $(If($NewBackIsWhite){'□'} Else {'■'});
    }

    [bool] CheckCanMoveTo([Position]$FromPos,[Position]$ToPos,$Tiles,$MoveCache)
    {
        return $this.OccupantAllegiance -ne [Allegiance]::None -and $MoveCache.IsValidMove($FromPos,$ToPos);
    }

    [System.Collections.Generic.List[Position]] GetMoves([Position]$from, [Allegiance]$allegiance, $board)
    {
        return $this.OccupantPiece::PieceRules.GetPossibleMoves([Position]$from, [string]$allegiance, $board)
    }

    [char] GetIcon()
    {
        $returnVal = '#';
        switch([int]$this.OccupantAllegiance)
        {
            ([int][Allegiance]::White) {$returnVal = [char]$([int]([char]$this.OccupantPiece::pieceIcon)+6); break;}
            ([int][Allegiance]::Black) {$returnVal = $this.OccupantPiece::pieceIcon; break;}
            ([int][Allegiance]::None) {$returnVal = $this.BackChar; break;}
        }
        return $returnVal;
    }

    [bool] MovePiece([Position]$FromPos,[Position]$ToPos,$Tiles,$MoveCache)
    {
        if($this.CheckCanMoveTo($FromPos,$ToPos,$Tiles,$MoveCache))
        {
            $Tiles[$ToPos.X,$ToPos.Y].OccupantPiece = $this.OccupantPiece;
            $this.OccupantPiece = $null;
            $Tiles[$ToPos.X,$ToPos.Y].OccupantAllegiance = $this.OccupantAllegiance;
            $this.OccupantAllegiance = [Allegiance]::None;
            return $true;
        }
        else
        {
            return $false;
        }
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

function ParseNotation([string]$notation,[ref]$ToPos,[ref]$FromPos,[ref]$TargetPiece)
{
    #notation to check if valid move
    if($($notation -match "([KQRBN])?([a-h])([1-8])([a-h])([1-8])"))
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
        $ToPos.Value.X = [char]($Matches[4]) % 97; #X values are alphabetical, % 97 returns their position in the alphabet zero indexed
        $ToPos.Value.Y = 7 - ($Matches[5] - 1);
        return $true;
    }
    else
    {
        return $false;
    }

}


[Tile[,]]$Grid = New-Object 'Tile[,]' 8,8;

GenerateBaseGrid $Grid;
$moveCache = [MoveCache]::new()


$continue = $true;
$whitesTurn = $true;

while($continue)
{
    $moveCache.UpdateCache($(If($whitesTurn){[Allegiance]::White}else{[Allegiance]::Black}),$Grid)
    
    echo $(If($whitesTurn) {"Whites Turn"} Else {"Blacks Turn"});
    $output = "  a  b  c  d  e  f  g  h  `n";

    For ($y = 0; $y -le 7;$y++)
    {
        $output += [Math]::Abs($y-8);
        For ($x = 0; $x -le 7;$x++)
        {
            $output += " " + $Grid[$x,$y].GetIcon() + " ";
        }
        $output += "`n";
    }

    echo $output;

    while($true)
    {
        $Move = Read-Host "Enter Move";

        if($Move -eq "exit")
        {
            $continue = $false;
            break;
        }
        else
        {
            #Target for movement
            [Position]$selectedTarget = [Position]::new(0,0)
            #Current Position
            [Position]$currentPosition = [Position]::new(0,0)
            #Expected Piece
            $selectedTargetPiece = $null;
            if(ParseNotation $Move ([ref]$selectedTarget) ([ref]$currentPosition) ([ref]$selectedTargetPiece))
            {
                if($Grid[$currentPosition.X,$currentPosition.Y].MovePiece($currentPosition,$selectedTarget,$Grid,$moveCache))
                {
                    $whitesTurn = -not $whitesTurn;
                    break;
                }
                else
                {
                    echo "Invalid Move";
                }
            }
            else
            {
                echo "Syntax Error. Use Format Ka1b2";
            }
        }
    }
}