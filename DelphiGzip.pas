unit DelphiGzip;

interface

uses
  Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  DsgnIntf, gzio, zlib;

type
  TZeroHundred = 0..100;

  THeader = set of (filename, comment);

  TAboutProperty = class(TPropertyEditor)
  public
	procedure Edit; override;
	function GetAttributes: TPropertyAttributes; override;
	function GetValue: string; override;
  end;

  TCompressionLevel = 1..9;
  TCompressionType = (Standard,Filtered,HuffmanOnly);
  TGzip = class(TComponent)
  private
	{ Private declarations }
	FGzipHeader : THeader;
	FAbout : TAboutProperty;
	FFileSource : string;
	FFileDestination : string;
	FDeleteSource : boolean;
	FComments : string;
	FCompressionLevel : TCompressionLevel;
	FCompressionType : TCompressionType;
	FWindowOnError : boolean;
	FOnProgress : TNotifyEvent;
	FProgress : integer;
	FProgressStep : TZeroHundred;
	FGzipFilename : string;
	FGzipComments : string;
  protected
	{ Protected declarations }
	procedure DoOnProgress; virtual;
	function gz_compress (var infile:file; outfile:gzFile): integer;
	function gz_uncompress (infile:gzFile; var outfile:file;
							fsize:longword) : integer;
  public
	{ Public declarations }
	constructor Create( AOwner: TComponent); override;
	procedure FileSwitch;
	function Gzip : integer;
	function Gunzip : integer;
	function getGzipInfo : integer;
	property GzipFilename : string
		 read FGzipFilename write FGzipFilename;
	property GzipComments : string
		 read FGzipComments write FGzipComments;
	property Progress : integer
		 read FProgress write FProgress;
  published
	{ Published declarations }
	property GzipHeader : THeader
		 read FGzipHeader write FGzipHeader;
	property About: TAboutProperty
		 read FAbout write FAbout;
	Property DeleteSource : boolean
		 read FDeleteSource write FDeleteSource;
	Property FileSource : string
		 read FFileSource write FFileSource;
	Property FileDestination : string
		 read FFileDestination write FFileDestination;
	Property Comments : string
		 read FComments write FComments;
	Property CompressionLevel : TCompressionLevel
		 read FCompressionLevel write FCompressionLevel;
	Property CompressionType : TCompressionType
		 read FCompressionType write FCompressionType;
	Property WindowOnError : boolean
		 read FWindowOnError write FWindowOnError;
	property ProgressStep : TZeroHundred
		 read FProgressStep write FProgressStep;
	property OnProgress : TNotifyEvent
		 read FOnProgress write FOnProgress;
  end;

  procedure Register;

implementation

uses utils;

const
  ASCII_FLAG  = $01; { bit 0 set: file probably ascii text }
  HEAD_CRC    = $02; { bit 1 set: header CRC present }
  EXTRA_FIELD = $04; { bit 2 set: extra field present }
  ORIG_NAME   = $08; { bit 3 set: original file name present }
  COMMENT_    = $10; { bit 4 set: file comment present }
  RESERVED    = $E0; { bits 5..7: reserved }

procedure TAboutProperty.Edit;
var utils : TUtils;
begin
   ShowMessage(utils.CreateAboutMsg('DelphiGZip'))
end;

function TAboutProperty.GetAttributes: TPropertyAttributes;
begin
  Result := [paMultiSelect, paDialog, paReadOnly];
end;

function TAboutProperty.GetValue: string;
begin
  Result := 'DelphiGzip';
end;

constructor TGzip.Create( AOwner: TComponent);
begin
   inherited Create( AOwner);
   CompressionLevel := 6;
   CompressionType := Standard;
   FileSource := 'data.dat';
   FileDestination := 'data.dat.gz';
   DeleteSource := False;
   WindowOnError := True;
   FProgressStep := 0;
   FComments := 'generated by DelphiZlib';
   FGzipHeader := [filename]
end;

procedure TGzip.DoOnProgress;
begin
	if Assigned (FOnProgress) then
	   FOnProgress (self)
end;

{ gz_compress ----------------------------------------------
# This code comes from minigzip.pas with some changes
# Original:
# minigzip.c -- usage example of the zlib compression library
# Copyright (C) 1995-1998 Jean-loup Gailly.
#
# Pascal tranlastion
# Copyright (C) 1998 by Jacques Nomssi Nzali
#
# 0 - No Error
# 1 - Read Error
# 2 - Write Error
# 3 - gzclose error
-----------------------------------------------------------}
function TGzip.gz_compress (var infile:file; outfile:gzFile): integer;
var
  len   : uInt;
  ioerr : integer;
  buf  : packed array [0..BUFLEN-1] of byte; { Global uses BSS instead of stack }
  errorcode : byte;
  fsize, lensize : longword;

begin
  errorcode := 0;
  Progress := 0;
  fsize := FileSize(infile);
  lensize := 0;
  if FProgressStep > 0 then DoOnProgress;

  while true do begin
	{$I-}
	blockread (infile, buf, BUFLEN, len);
	{$I+}

	ioerr := IOResult;
	if (ioerr <> 0) then begin
	  errorcode := 1;
	  break
	end;

	if (len = 0) then break;

	{$WARNINGS OFF}{Comparing signed and unsigned types}
	if (gzwrite (outfile, @buf, len) <> len) then begin
	{$WARNINGS OFF}
	  errorcode := 2;
	  break
	end;

	if FProgressStep > 0 then begin
	   {$WARNINGS OFF}{Calculate progress and raise event}
	   lensize := lensize + len;
	   if ((lensize / fsize) * 100 >= FProgress + FProgressStep)
						or (lensize = fsize) then begin
		  FProgress := Trunc((lensize / fsize) * 100);
		  DoOnProgress
	   end
	   {$WARNINGS ON}
	end
  end; {WHILE}

  closeFile (infile);
  if (gzclose (outfile) <> 0{Z_OK}) then errorcode := 3;

  gz_compress := errorcode;
end;

{ gz_uncompress ----------------------------------------------
# This code comes from minigzip.pas with some changes
# Original:
# minigzip.c -- usage example of the zlib compression library
# Copyright (C) 1995-1998 Jean-loup Gailly.
#
# Pascal tranlastion
# Copyright (C) 1998 by Jacques Nomssi Nzali
#
# 0 - No error
# 1 - Read Error
# 2 - Write Error
# 3 - gzclose Error
-----------------------------------------------------------}
function TGzip.gz_uncompress (infile:gzFile; var outfile:file;
							  fsize:longword) : integer;
var
  len     : integer;
  written : uInt;
  buf  : packed array [0..BUFLEN-1] of byte; { Global uses BSS instead of stack }
  errorcode : byte;
  lensize : longword;
begin
  errorcode := 0;
  FProgress := 0;
  lensize := 0;
  if FProgressStep > 0 then DoOnProgress;

  while true do begin

	len := gzread (infile, @buf, BUFLEN);
	if (len < 0) then begin
	   errorcode := 1;
	   break
	end;
	if (len = 0)
	  then break;

	{$I-}
	blockwrite (outfile, buf, len, written);
	{$I+}
	{$WARNINGS OFF}{Comparing signed and unsigned types}
	if (written <> len) then begin
	{$WARNINGS ON}
	   errorcode := 2;
	   break
	end;

	if FProgressStep > 0 then begin
	   {$WARNINGS OFF}
	   lensize := lensize + len;
	   if ((lensize / fsize) * 100 >= FProgress + FProgressStep)
						or (lensize = fsize) then begin
		  FProgress := Trunc((lensize / fsize) * 100);
		  DoOnProgress
	   end
	   {$WARNINGS ON}
	end
  end; {WHILE}



  if (gzclose (infile) <> 0{Z_OK}) then begin
	 if FWindowOnError then
		MessageDlg('gzclose Error.', mtError, [mbAbort], 0);
	 errorcode := 3
  end;

  gz_uncompress := errorcode
end;

{***************************************************************
* The public part
***************************************************************}

procedure TGzip.FileSwitch;
var s : string;
begin
   s := FFileSource;
   FFileSource := FFileDestination;
   FFileDestination := s;
end;

{ Gzip ---------------------------------------------------------
# Returns 0 - File compressed
#         1 - Could not open FFileIn
#         2 - Could not create FFileOut
#      >100 - Error-100 in gz_compress
---------------------------------------------------------------}
function TGzip.Gzip : integer;
var outmode : string;
	s : string;
	infile  : file;
	outfile : gzFile;
	errorcode : integer;
	flags : uInt;
	stream : gz_streamp;
	p : PChar;
	ioerr : integer;
begin
  AssignFile (infile, FFileSource);
  {$I-}
  Reset (infile,1);
  {$I+}
  ioerr := IOResult;
  if (ioerr <> 0) then begin
	if FWindowOnError then
		 MessageDlg('Can''t open: '+FFileSource, mtError, [mbAbort], 0);
	errorcode := 1
  end
  else begin
	  outmode := 'w  ';
	  s := IntToStr(FCompressionLevel);
	  outmode[2] := s[1];
	  case FCompressionType of
		   Standard    : outmode[3] := ' ';
		   HuffmanOnly : outmode[3] := 'h';
		   Filtered    : outmode[3] := 'f';
	  end;
	  flags := 0;
	  if (filename in FGzipHeader) then flags := ORIG_NAME;
	  if (comment  in FGzipHeader) then flags := flags + COMMENT_;

	  outfile := gzopen (FFileDestination, outmode, flags);

	  if (outfile = NIL) then begin
		 if FWindowOnError then
			  MessageDlg('Can''t open: '+FFileDestination, mtError, [mbAbort], 0);
		 close( infile);
		 errorcode := 2
	  end
	  else begin
		 { if flags are set then write them }
		 stream := gz_streamp(outfile);

		 if (filename in FGzipHeader) then
		 begin
                        s := ExtractFilename(FFileSource);
			p := PChar(s);
			blockWrite( stream^.gzfile, p[0], length(s)+1);
			stream^.startpos := stream^.startpos + length(s) + 1
		 end;
		 if (comment  in FGzipHeader) then
		 begin
			p := PChar(FComments);
			blockWrite( stream^.gzfile, p[0], length(FComments)+1);
			stream^.startpos := stream^.startpos + length(FComments) + 1
		 end;

		 { start compressing }
		 errorcode := gz_compress(infile, outfile);
		 if errorcode <> 0 then errorcode := errorcode+100
		 else
			if FDeleteSource then erase (infile);
	  end
   end;
   Gzip := errorcode
end;

{ Gzip ---------------------------------------------------------
# Returns 0 - File decompressed
#         1 - Could not open FFileIn
#         2 - Could not create FFileOut
#         3 - FFileIn not a valid gzip-file
---------------------------------------------------------------}
function TGzip.Gunzip : integer;
var //len : integer;
	infile : gzFile;
	outfile : file;
	ioerr : integer;
	errorcode : integer;
	fsize : longword;
	s : gz_streamp;
begin
  errorcode := 0;

  infile := gzopen (FFileSource, 'r', 0);
  if (infile = NIL) then begin
	if FWindowOnError then
	   MessageDlg('Can''t open: '+FFileSource, mtError, [mbAbort], 0);
	errorcode := 1
  end
  else begin
	s := gz_streamp(infile);
	fsize := FileSize( s^.gzfile);

	AssignFile (outfile, FFileDestination);
	{$I-}
	Rewrite (outfile,1);
	{$I+}
	ioerr := IOResult;
	if (ioerr <> 0) then begin
		if FWindowOnError then
		   MessageDlg('Can''t create: '+FFileDestination, mtError, [mbAbort], 0);
		errorcode := 2
	end
	else begin
		{ We could open all files, so time for uncompressing }
		gz_uncompress (infile, outfile, fsize);
		if FDeleteSource then DeleteFile(FFileSource);

	   {$I-}
	   close (outfile);
	   {$I+}
	   ioerr := IOResult;
	   if (ioerr <> 0) then begin
		  if FWindowOnError then
			 MessageDlg('Can''t close file '+FFileDestination, mtError, [mbAbort], 0);
		  halt(1)
	   end
	end
  end;

  Gunzip := errorcode
end;

{ getGzipInfo ==================================================================
# todo: check for more errorcodes
#
# Errorcodes:
# 0 - No error. Info can be found in GzipFilename
#									 GzipComments
# 1 - Can't open FFileSource
# 2 - Not a Gzip file or invalid header
# 3 - Can't handle this field
# 4 -
===============================================================================}
function TGzip.getGzipInfo : integer;
// todo: check for eof, corrupt files etc etc
var len, dummy: uInt;
	infile : file;
	head : array[0..9] of byte;
	ch : char;
	str : string;
	errorcode, ioerr : integer;
begin
   errorcode := 0;
   // Clean up old values
   FGzipFilename := '';
   FGzipComments := '';

   AssignFile( infile, FFileSource);
   {$I-}
   Reset (infile,1);
   {$I+}
   ioerr := IOResult;
   if (ioerr <> 0) then begin
	  if FWindowOnError then
		 MessageDlg('Can''t open: '+FFileSource, mtError, [mbAbort], 0);
	  errorcode := 1
   end else begin

	  TRY
		 blockRead( infile, head, 10, len);

		 if (head[0] <> $1F) or (head[1] <> $8B) or (len<10) then begin
			// Not a Gzip-file or header not valid
			errorcode := 2;
			abort
		 end;

		 if (head[2] <> Z_DEFLATED) or ((head[3] and RESERVED) <> 0) then begin
			// Can not handle this
			errorcode := 3;
			abort
		 end;

		 if ((head[3] and EXTRA_FIELD) <> 0) then begin
			// the extra field
			blockRead(infile, len, 1);
			blockread(infile, dummy, 1);
			len := len + (dummy shl 8);
			if FileSize( infile) < int(len+12) then begin
			   errorcode := 2;
			   abort
			end;
			seek( infile, len + 12) 		// just throw it away
		 end;

		 if ((head[3] and ORIG_NAME) <> 0) then begin
			// the original file name
			str := '';
			blockread( infile, ch, 1);
			while (ch <> char(0)) and not eof( infile) do begin
			   str := str + ch;
			   blockread( infile, ch, 1)
			end;
			if eof( infile) then begin
			   errorcode := 2;
			   abort
			end;
			FGzipFilename := str
		 end;

		 if ((head[3] and COMMENT_) <> 0) then begin
			// the comments
			str := '';
			blockread( infile, ch, 1);
			while (ch <> char(0)) and not eof( infile) do begin
			   str := str + ch;
			   blockread( infile, ch, 1)
			end;
			if eof( infile) then begin
			   errorcode := 2;
			   abort
			end;
			FGzipComments := str
		 end

	  FINALLY
		CloseFile ( infile)
	  end
   end;
   getGzipInfo := errorcode
end;

procedure Register;
begin
  RegisterComponents('Samples', [TGzip]);
  RegisterPropertyEditor(TypeInfo(TAboutProperty), TGzip, 'ABOUT', TAboutProperty);
end;

end.
