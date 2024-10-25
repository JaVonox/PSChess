#Movements
class Position {
    [int]$x
    [int]$y

    Position([int]$nX, [int]$nY) {
        $this.X = $nX
        $this.Y = $nY
    }

    [bool] Equals([object]$obj) {
        if ($obj -isnot [Position]) { return $false }
        return $this.X -eq $obj.X -and $this.Y -eq $obj.Y
    }

    [int] GetHashCode() {
        return $this.X.GetHashCode() -bxor $this.Y.GetHashCode()
    }
}

class IMoveRule {
    [System.Collections.Generic.HashSet[Position]] GetPossibleMoves([Position]$from, [string]$allegiance, $board) {
        throw "Must be implemented"
    }
}

#Movement Rules

#class DirectionalRule : IMoveRule
#{
#    [int]$DirX
#    [int]$DirY
#    [bool]$Repeating
#    
#    DirectionalRule()
#}
#Pieces


class PieceTypeBase
{
    static [char]$pieceIcon;

    static [bool] IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles){
    return $targetX -ge 0 -and $targetX -le 7 -and $targetY -ge 0 -and $targetY -le 7 -and ( -not ($allegiance -eq $Tiles[$targetX,$targetY].OccupantAllegiance));
    }
}

class Pawn : PieceTypeBase
{
    static [char]$pieceIcon = '♙';

    static [bool] IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles){
    $yChange = if ($allegiance -eq [Allegiance]::White) {-1} Else {1}
    #Do this early to prevent access to bad array indexes
    if(-not [PieceTypeBase]::IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles)){return $false;}
    
    #check if we would take a piece from this operation. If we can take a piece we can move diagonally
    $isEnemyTile = $(if ($allegiance -eq [Allegiance]::White) { $Tiles[$targetX,$targetY].OccupantAllegiance -eq [Allegiance]::Black } else { $Tiles[$targetX,$targetY].OccupantAllegiance -eq [Allegiance]::White});
    
    if(-not $isEnemyTile)
    {
        #If we query a tile and it is not an enemy tile we can move to it if it is forward
        return ($myY + $yChange -eq $targetY -and $targetX -eq $myX);
    }
    else
    {
        #If we query a tile and it is an enemy tile we can not move to it if it is forward, but we can if it is diagonal in the direction we are moving
        return ($myY + $yChange -eq $targetY) -and ($targetX -eq ($myX + 1)) -or ($targetX -eq ($myX - 1));
    }

    }
}

class Rook : PieceTypeBase
{
    static [char]$pieceIcon = '♖';

    static [bool] IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles){
    return [PieceTypeBase]::IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles) -and ($myX -eq $targetX -xor $myY -eq $targetY);
    }
}

class Knight : PieceTypeBase
{
    static [char]$pieceIcon = '♘';

    static [bool] IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles){
    $xChange = [Math]::Abs($targetX - $myX);
    $yChange = [Math]::Abs($targetY - $myY);
    $totalChange = $xChange + $yChange;
    return [PieceTypeBase]::IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles) -and ($xChange -eq 2 -or $yChange -eq 1 -xor $xChange -eq 1 -or $yChange -eq 2) -and ($totalChange -eq 3);
    }
}

class Bishop : PieceTypeBase
{
    static [char]$pieceIcon = '♗';

    static [bool] IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles){
    $xChange = [Math]::Abs($targetX - $myX);
    $yChange = [Math]::Abs($targetY - $myY);
    $difference = [Math]::Abs($xChange - $yChange);
    return [PieceTypeBase]::IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles) -and ($difference -eq 0);
    }
}

class King : PieceTypeBase
{
    static [char]$pieceIcon = '♔';

    static [bool] IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles){
    $yWithinRange = ($targetY -eq $myY + 1 -or $targetY -eq $myY - 1 -or $targetY -eq $myY);
    $xWithinRange = ($targetX -eq $myX + 1 -or $targetX -eq $myX - 1 -or $targetX -eq $myX);
    $noChange = ($targetX -eq $myX) -and ($targetY -eq $myY);
    return [PieceTypeBase]::IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles) -and ($yWithinRange -and $xWithinRange -and (-not $noChange));
    }
}

class Queen : PieceTypeBase
{
    static [char]$pieceIcon = '♕';

    static [bool] IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles){
    $xChange = [Math]::Abs($targetX - $myX);
    $yChange = [Math]::Abs($targetY - $myY);
    $difference = [Math]::Abs($xChange - $yChange);
    return [PieceTypeBase]::IsValidMove($targetX,$targetY,$myX,$myY,$allegiance,$Tiles) -and ($difference -eq 0) -or ($myX -eq $targetX -xor $myY -eq $targetY);
    }
}

enum Allegiance
{
    None
    White
    Black
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

    [bool] CheckCanMoveTo($newX,$newY,$myX,$myY,$Tiles)
    {
        return $this.OccupantPiece -ne $null -and $this.OccupantPiece::IsValidMove($newX,$newY,$myX,$myY,$this.OccupantAllegiance,$Tiles);
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

    #Compare a char ref to determine if it matches this piece
    [bool] CanBeSelected([System.Type]$Comparitor,[bool]$IsWhite)
    {
        return $($this.OccupantPiece -eq $Comparitor) -and $(If($IsWhite) {$this.OccupantAllegiance -eq [Allegiance]::White} Else{$this.OccupantAllegiance -eq [Allegiance]::Black});
    }

    [bool] MovePiece([int]$targetX,[int]$targetY,[int]$myX,[int]$myY,$Tiles)
    {
        if($this.CheckCanMoveTo($targetX,$targetY,$myX,$myY,$Tiles))
        {
            $Tiles[$targetX,$TargetY].OccupantPiece = $this.OccupantPiece;
            $this.OccupantPiece = $null;
            $Tiles[$targetX,$TargetY].OccupantAllegiance = $this.OccupantAllegiance;
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

function ParseNotation([string]$notation,[ref]$targetY,[ref]$targetX,[ref]$moveFromY,[ref]$moveFromX,[ref]$TargetPiece)
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
        $moveFromX.Value = [char]($Matches[2]) % 97; #X values are alphabetical, % 97 returns their position in the alphabet zero indexed
        $moveFromY.Value = 7 - ($Matches[3] - 1);
        $targetX.Value = [char]($Matches[4]) % 97; #X values are alphabetical, % 97 returns their position in the alphabet zero indexed
        $targetY.Value = 7 - ($Matches[5] - 1);
        return $true;
    }
    else
    {
        return $false;
    }

}

[Tile[,]]$Grid = New-Object 'Tile[,]' 8,8;

GenerateBaseGrid $Grid;

$continue = $true;
$whitesTurn = $true;

while($continue)
{
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
            $selectedTargetY = $null;
            $selectedTargetX = $null;
            #Current Position
            $selectedMoveY = $null;
            $selectedMoveX = $null;
            #Expected Piece
            $selectedTargetPiece = $null;
            if(ParseNotation $Move ([ref]$selectedTargetY) ([ref]$selectedTargetX) ([ref]$selectedMoveY) ([ref]$selectedMoveX) ([ref]$selectedTargetPiece))
            {
                if($Grid[$selectedMoveX,$selectedMoveY].CanBeSelected($selectedTargetPiece,$whitesTurn) -and $Grid[$selectedMoveX,$selectedMoveY].MovePiece($selectedTargetX,$selectedTargetY,$selectedMoveX,$selectedMoveY,$Grid))
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