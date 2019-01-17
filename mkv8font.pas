{
   Copyright (C) 2019 Jerome Shidel

   This program is free software; you can redistribute it and/or modify
   it under the terms of the GNU General Public License as published by
   the Free Software Foundation; either version 2 of the License, or
   (at your option) any later version.

   This program is distributed in the hope that it will be useful,
   but WITHOUT ANY WARRANTY; without even the implied warranty of
   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
   GNU General Public License for more details.

   You should have received a copy of the GNU General Public License along
   with this program; if not, write to the Free Software Foundation, Inc.,
   51 Franklin Street, Fifth Floor, Boston, MA 02110-1301 USA.
}
program MakeV8Font;

const
    CRLF=#$0d#$0a;
    V8FONT: String ='V8FONT'+CRLF;
    EOF: Char = #26;

type
    TBlock=record
        Style : byte;
        Size : word;
        First, Count : word;
        Width, Height : word;
    end;

procedure SetROMFont(ASize:byte); assembler;
asm
    mov     ah, ASize
    mov     al, 1
    cmp     ah, 14
    je      @@LoadFont
    mov     al, 2
    cmp     ah, 8
    je      @@LoadFont
    mov     al, 4
@@LoadFont:
    mov     ah, 11h
    mov     bl, 00h
    int     10h
end;

procedure SetCustomFont(ASize:byte; AFont : pointer); assembler;
asm
    push    bp
    push    es
    mov     bh, ASize
    les     bp, AFont
    mov     ax, 1100h
    mov     bl, 0
    mov     cx, 0100h
    mov     dx, 0000h

    int     10h
    pop     es
    pop     bp
end;

function GetFontHeight : byte; assembler;
asm
    push    es
    push    di
    mov     ax, 0040h
    mov     es, ax
    mov     di, 0085h
    mov     al, [es:di]
    pop     di
    pop     es
end;

function GetROMFontPtr(ASet:byte; Upper, Alt:Boolean) : pointer; assembler;
asm
    push    es
    push    bp
    mov     ax, 1130h
    mov     cl, Alt

    mov     bl, ASet
    mov     bh, 02h
    cmp     bl, 14
    je      @@CheckAlt14
    mov     bh, 06h
    cmp     bl, 16
    je      @@CheckAlt16
    mov     bh, 03h
    mov     bl, Upper
    cmp     bl, False
    je      @@GetPointer
    inc     bh
    jmp     @@GetPointer
@@CheckAlt14:
    cmp     cl, True
    jne     @@GetPointer
    mov     bh, 05h
    jmp     @@GetPointer
@@CheckAlt16:
    cmp     cl, True
    jne     @@GetPointer
    mov     bh, 07h
@@GetPointer:
    int     10h
    mov     dx, es
    mov     ax, bp
    pop     bp
    pop     es
    mov     bh, ASet
    mov     bl, Upper
    cmp     bh, 8
    je      @@Done
    cmp     bl, False
    je      @@Done
    push    dx
    push    ax
    mov     ax, 0080h
    mul     cx
    pop     bx
    add     ax, bx
    pop     dx
@@Done:
end;

procedure PrintDots(AValue:Byte);
var
    I : integer;
begin
    for I := 0 to 7 do
        if ( AValue shr (7 - I) and $1 = $1 ) then
            Write(#$B2)
        else
            Write(' ');
end;

procedure Delay(Ms:word); assembler;
asm
    push    di
    push    es
    xor     dx, dx
    mov     ax, Ms
    mov     cx, 55
    div     cx
    mov  	dx, 0040h
    mov		es, dx
    mov		di, 006Ch
    mov     dx, [es:di]
@@Waiting:
    hlt
    mov     cx, [es:di]
    cmp     cx, dx
    je      @@Waiting
    mov     dx, cx
    cmp     ax, 0
    je      @@Done
    dec     ax
    jmp     @@Waiting
@@Done:
    pop     es
    pop     di
end;

function ConvertFont(AFileName: String) : integer;
var
    F : File;
    P, R : Pointer;
    S : LongInt;
    H, E, T : integer;
    C : array[0..255] of boolean;
    LG, G, N, L, I : integer;
    A, B : Byte;
    V : String;
    Block : TBlock;
begin
    FileMode:= 0;
    Assign(F, AFileName);
    Reset(F,1);
    S := FileSize(F);
    GetMem(P, S);
    BlockRead(F, P^, S);
    Close(F);
    FillChar(C, Sizeof(C), False);
    H := S div 256;
    if (S mod 256 <> 0) or (H > 30) or (H < 4) then begin
        WriteLn('Invalid font file');
        Halt(3);
    end;
    if (H <> 8) and (H <> 14) and (H <> 16) then
        FillChar(C, Sizeof(C), True)
    else begin
        repeat
            LG := -1;
            I := 0;
            repeat
                N := I and $7F;
                G := I shr 7;
                if LG <> G then
                    R := GetROMFontPtr(H, G = 1, False);
                LG := G;
                for L := 0 to H - 1 do
                    begin
                        A:=Mem[Seg(R^):Ofs(R^) + (N * H) + L];
                        B:=Mem[Seg(P^):Ofs(P^) + (G * $80 * H) + (N * H) + L];
                        PrintDots(A);
                        Write('  ');
                        PrintDots(B);
                        WriteLn;
                    end;
                 Write('Character #', G * $80 + N, ', Approve (y/N/q/p)?');
                 ReadLn(V);
                 Val(V, T, E);
                 if E = 0 then
                    I := T
                 else if V = 'q' then continue
                 else if (V = 'p') or (V = 'P') then
                    dec(I)
                 else begin
                    C[G * $80 + N] := (V = 'y') or (V = 'Y');
                    Inc(I);
                 end;
            until (V = 'q') or (I > 255);
            SetCustomFont(H, P);
            T := 0;
            for I := 0 to 255 do
                if C[I] = True then begin
                    Write(Chr(I));
                    Inc(T);
                end;
            WriteLn;
            Write(T, ' font characters, Continue (Y/n/q)?');
            ReadLn(V);
            SetRomFont(H);
        until (V <> 'n') or (V <> 'N');
    end;
    Write('Text Comment?');
    ReadLn(V);
    AFileName := Copy(AFileName, 1, Pos('.', AFileName) - 1) + '.V8F';
    WriteLn('Saving ', AFileName);
    Assign(F, AFilename);
    Rewrite(F, 1);
    BlockWrite(F, V8FONT[1], Length(V8FONT));
    if V <> '' then begin
        BlockWrite(F, V[1], Length(V));
        V := CRLF;
        BlockWrite(F, V[1], Length(V));
    end;
    BlockWrite(F, EOF, Sizeof(EOF));
    I := 0;
    Block.Style := 1;
    Block.Width := 8;
    Block.Height := H;
    Block.First := 0;
    Block.Count := 0;
    while I < 255 do begin
        if C[I] = True then begin
            if Block.Count = 0 then
                Block.First := I;
            Inc(Block.Count);
        end;
        if (Block.Count > 0) and ((C[I] = False) or (I = 255)) then begin
            Block.Size := (Sizeof(Block) - 1) + H * Block.Count;
            BlockWrite(F, Block, Sizeof(Block));
            R := Ptr(Seg(P^),Ofs(P^) + (Block.First * H));
            BlockWrite(F, R^, H * Block.Count);
            Block.Count := 0;
        end;
        Inc(I);
    end;
    A := 0;
    BlockWrite(F, A, Sizeof(A));
    Close(F);
end;

begin
    ConvertFont (ParamStr(1));
end.