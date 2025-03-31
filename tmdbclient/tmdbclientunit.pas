unit tmdbclientunit;

{$mode objfpc}{$H+}

interface

uses
  Classes, SysUtils, Forms, Controls, Graphics, Dialogs, StdCtrls, Grids,
  ExtCtrls, Menus, ComCtrls, Process, fpjson, jsonparser, base64, LCLType,
  FPReadPNG, FPReadJPEG, Types;

type
  TConfig = record
    TMDBApiKey: string;
    Left: Integer;
    Top: Integer;
  end;

type

  { TTMDBClientForm }

  TTMDBClientForm = class(TForm)
    BottomPanel: TPanel;
    DataStringGrid: TStringGrid;
    FilterPanel: TPanel;
    ToolbarImageList: TImageList;
    Panel1: TPanel;
    ToolBar: TToolBar;
    ToolButton1: TToolButton;
    ToolButton2: TToolButton;
    ToolButton3: TToolButton;
    ToolButton4: TToolButton;
    ToolButton5: TToolButton;
    TypesImageList: TImageList;
    SearchButton: TButton;
    TVCheck: TCheckBox;
    SearchEdit: TEdit;
    SmallPoster: TImage;
    SmallPosterPanel: TPanel;
    SearchPanel: TPanel;
    StatusBar1: TStatusBar;
    GridView: TStringGrid;
    TopPanel: TPanel;
    TrayIcon1: TTrayIcon;
    MovieCheck: TCheckBox;
    procedure FormCreate(Sender: TObject);
    procedure SearchButtonClick(Sender: TObject);
    procedure SearchEditKeyDown(Sender: TObject; var Key: Word; Shift: TShiftState);
    procedure GridViewDrawCell(Sender: TObject; aCol, aRow: Integer;
      aRect: TRect; aState: TGridDrawState);
    procedure GridViewHeaderClick(Sender: TObject; IsColumn: Boolean;
      Index: Integer);
    procedure GridViewSelection(Sender: TObject; aCol, aRow: Integer);
  private
    FJsonData: string;
    procedure LoadSearchResults(const AJsonStr: string);
    procedure UpdateDisplayGrid;
    procedure LoadImageFromBase64(const Base64Str: string);
    procedure ExecuteSearch(const SearchTerm: string; const APIKey: string);
    function LoadJsonFromFile: Boolean;
    function LoadConfig(const AFileName: string): TConfig;
  public
    { public declarations }
  end;

var
  TMDBClientForm: TTMDBClientForm;
  Config: TConfig;



implementation

{$R *.lfm}

function TTMDBClientForm.LoadConfig(const AFileName: string): TConfig;
var
  JSONData: TJSONData;
  JSONObject: TJSONObject;
  JSONString: TStringList;
begin
  // Set default values in case keys are missing
  Result.TMDBApiKey := '';
  Result.Left := 0;
  Result.Top := 0;

  if not FileExists(AFileName) then
    raise Exception.Create('Config file not found: ' + AFileName);

  JSONString := TStringList.Create;
  try
    JSONString.LoadFromFile(AFileName);
    JSONData := GetJSON(JSONString.Text);
    try
      if JSONData.JSONType <> jtObject then
        raise Exception.Create('Invalid JSON format in ' + AFileName);

      JSONObject := TJSONObject(JSONData);

      // Read the values from the JSON object, using default values if necessary
      Result.TMDBApiKey := JSONObject.Get('tmdbapikey', '');
      Result.Left := JSONObject.Get('left', 0);
      Result.Top := JSONObject.Get('top', 0);
    finally
      JSONData.Free;
    end;
  finally
    JSONString.Free;
  end;
end;

procedure TTMDBClientForm.FormCreate(Sender: TObject);
begin

  Config := LoadConfig('tmdbclient.config');

  // Load the JSON file during form creation
  if LoadJsonFromFile then
  begin
    // If JSON data was loaded successfully, display it
    LoadSearchResults(FJsonData);
  end
end;

function TTMDBClientForm.LoadJsonFromFile: Boolean;
var
  OutputLines: TStringList;
  JsonFilePath: string;
begin
  Result := False;

  // Check if a file named 'searchresults.json' exists
  JsonFilePath := ExtractFilePath(Application.ExeName) + 'searchresults.json';
  if FileExists(JsonFilePath) then
  begin
    OutputLines := TStringList.Create;
    try
      OutputLines.LoadFromFile(JsonFilePath);
      FJsonData := OutputLines.Text;
      if Trim(FJsonData) = '' then
      begin
        ShowMessage('Error: searchresults.json is empty.');
        Exit;
      end;
      Result := True;
    finally
      OutputLines.Free;
    end;
  end;
end;

procedure TTMDBClientForm.SearchButtonClick(Sender: TObject);
var
  SearchTerm: string;
begin
  SearchTerm := Trim(SearchEdit.Text);
  if SearchTerm = '' then Exit;  // Skip empty searches

  ExecuteSearch(SearchTerm, Config.TMDBApiKey);
end;

procedure TTMDBClientForm.ExecuteSearch(const SearchTerm: string; const APIKey: string);
var
  curDir, exeName, output: string;
  exitStatus, ret: integer;
  args: TStringArray;
begin
  // Set the current directory and executable path.
  curDir := ExtractFilePath(Application.ExeName);
  exeName := curDir + 'tmdbclientdataprovider';
  {$IFDEF WINDOWS}
  if not FileExists(exeName) then
    exeName := exeName + '.exe';
  {$ENDIF}
  if not FileExists(exeName) then
  begin
    ShowMessage('Error: Executable not found: ' + exeName);
    Exit;
  end;

  // Prepare command line arguments including the API key flag
  if APIKey <> '' then
    args := ['--api-key', APIKey, 'search', SearchTerm]
  else
    args := ['search', SearchTerm];

  // Call the RunCommandIndir function.
  ret := RunCommandIndir(curDir, exeName, args, output, exitStatus);
  //ShowMessage(output);

  // Check for errors and load the JSON file if available.
  if exitStatus = 0 then
  begin
    LoadSearchResults(output);
  end
  else
    ShowMessage('Command execution failed with exit status: ' + IntToStr(exitStatus));
end;

procedure TTMDBClientForm.SearchEditKeyDown(Sender: TObject; var Key: Word;
  Shift: TShiftState);
begin
  if Key = VK_RETURN then
  begin
    // Execute search when Enter key is pressed
    SearchButtonClick(Sender);
    Key := 0;  // Prevent default action
  end;
end;

procedure TTMDBClientForm.UpdateDisplayGrid;
var
  avail: Integer;
begin
  // Configure GridView with only the visible columns.
  GridView.Columns.Clear;
  GridView.AutoFillColumns := False;
  // Use the same row count as DataStringGrid.
  GridView.RowCount := DataStringGrid.RowCount;
  GridView.FixedRows := 1;
  // Set a row height large enough for two lines of text.
  GridView.DefaultRowHeight := 40;  // Adjust this value as needed

  with GridView.Columns.Add do
  begin
    Title.Caption := 'Type';
    Width := 50;
  end;
  with GridView.Columns.Add do
  begin
    Title.Caption := 'Released';
    Width := 80;
  end;
  with GridView.Columns.Add do
  begin
    Title.Caption := 'Title';
    // Width will be adjusted.
  end;

  avail := GridView.ClientWidth - (GridView.ColWidths[0] + GridView.ColWidths[1]);
  if avail > 0 then
    GridView.ColWidths[2] := avail;

  // Force a redraw.
  GridView.Invalidate;
end;

procedure TTMDBClientForm.GridViewDrawCell(Sender: TObject; aCol, aRow: Integer;
  aRect: TRect; aState: TGridDrawState);
var
  mediatype, fulltitle, origTitle: string;
  ImgIndex: Integer;
  ts: TTextStyle;
  lineRect: TRect;
begin
  with GridView.Canvas do
  begin
    // For the header row, just draw the header text.
    if aRow = 0 then
    begin
      Font.Color := clBlack;
      Font.Style := [fsBold];
      TextRect(aRect, aRect.Left + 2, aRect.Top + 2, GridView.Cells[aCol, aRow]);
      Exit;
    end;

    case aCol of
      0: // Type column: draw image icon.
        begin
          mediatype := LowerCase(DataStringGrid.Cells[0, aRow]);
          if mediatype = 'tv' then
            ImgIndex := 1
          else if mediatype = 'movie' then
            ImgIndex := 2
          else
            ImgIndex := 0;
          if Assigned(TypesImageList) then
            TypesImageList.Draw(GridView.Canvas,
              aRect.Left + (aRect.Width - TypesImageList.Width) div 2,
              aRect.Top + (aRect.Height - TypesImageList.Height) div 2, ImgIndex);
        end;
      1: // Released column.
        begin
          Font.Color := clBlack;
          TextRect(aRect, aRect.Left + 2, aRect.Top + 2, DataStringGrid.Cells[1, aRow]);
        end;
      2: // Title column: Draw full_title and original_title with separate formatting
        begin
          fulltitle := DataStringGrid.Cells[2, aRow];
          origTitle := DataStringGrid.Cells[4, aRow];

          // Define the first line rectangle (top half of the cell)
          lineRect := aRect;
          lineRect.Bottom := (aRect.Top + aRect.Bottom) div 2;

          // Draw first line in black
          Font.Color := clBlack;
          ts := TextStyle;
          ts.SingleLine := True;
          ts.Alignment := taLeftJustify;
          ts.Layout := tlCenter;
          TextRect(lineRect, lineRect.Left + 2, 0, fulltitle, ts);

          // Define the second line rectangle (bottom half of the cell)
          lineRect := aRect;
          lineRect.Top := (aRect.Top + aRect.Bottom) div 2;

          // Draw second line in medium gray
          Font.Color := clMedGray;
          TextRect(lineRect, lineRect.Left + 2, 0, origTitle, ts);
        end;
    end;
  end;
end;

procedure TTMDBClientForm.GridViewHeaderClick(Sender: TObject; IsColumn: Boolean; Index: Integer);
var
  i, j, k, rowCount: Integer;
  SortList: TStringList;
  DateValue: TDateTime;
  SortValue, Title: string;
  TempGrid: TStringGrid;
begin
  if not IsColumn then Exit; // Only handle column header clicks

  // Determine which DataStringGrid column to use for sorting
  case Index of
    0: j := 0; // Type
    1: j := 1; // Released
    2: j := 2; // Title (full_title)
    else Exit;
  end;

  // Create a temporary grid to hold the data while sorting
  TempGrid := TStringGrid.Create(nil);
  try
    // Configure TempGrid to match DataStringGrid
    TempGrid.RowCount := DataStringGrid.RowCount;
    TempGrid.ColCount := DataStringGrid.ColCount;

    // Copy all data from DataStringGrid to TempGrid
    for i := 0 to DataStringGrid.RowCount - 1 do
      for k := 0 to DataStringGrid.ColCount - 1 do
        TempGrid.Cells[k, i] := DataStringGrid.Cells[k, i];

    // Create a sorted list to manage the row order
    SortList := TStringList.Create;
    try
      SortList.Sorted := True;

      // Skip the header row (row 0)
      rowCount := DataStringGrid.RowCount - 1;

      // Add each row to the sort list with a key based on the sort column
      for i := 1 to rowCount do
      begin
        SortValue := '';

        case j of
          0: begin // Type column
            // Sort by the actual media type value
            SortValue := DataStringGrid.Cells[j, i];
          end;
          1: begin // Released column (date)
            // Make sure dates are consistently formatted for sorting
            if TryStrToDate(DataStringGrid.Cells[j, i], DateValue) then
              SortValue := FormatDateTime('yyyy-mm-dd', DateValue)
            else
              SortValue := '9999-99-99'; // Put invalid dates at the end
          end;
          2: begin // Title column
            // Get the full title
            Title := DataStringGrid.Cells[j, i];

            // Remove leading "The " or "A " for sorting purposes
            if (Length(Title) > 4) and (Copy(Title, 1, 4) = 'The ') then
              SortValue := Copy(Title, 5, Length(Title))
            else if (Length(Title) > 2) and (Copy(Title, 1, 2) = 'A ') then
              SortValue := Copy(Title, 3, Length(Title))
            else
              SortValue := Title;
          end;
        end;

        // Make sure each key is unique by appending the row number
        SortValue := SortValue + #9 + IntToStr(i);
        SortList.AddObject(SortValue, TObject(PtrInt(i)));
      end;

      // If already sorted in ascending order, reverse the sort
      if Tag = Index then
      begin
        // Toggle sort direction
        Tag := -Index;

        // Create a new list with descending order
        for i := SortList.Count - 1 downto 0 do
        begin
          // Get the original row index
          k := PtrInt(SortList.Objects[i]);

          // Copy from temp grid back to DataStringGrid in new order
          for j := 0 to DataStringGrid.ColCount - 1 do
            DataStringGrid.Cells[j, SortList.Count - i] := TempGrid.Cells[j, k];
        end;
      end
      else
      begin
        // Set ascending order
        Tag := Index;

        // Copy from temp grid back to DataStringGrid in sorted order
        for i := 0 to SortList.Count - 1 do
        begin
          // Get the original row index
          k := PtrInt(SortList.Objects[i]);

          // Copy all columns for this row
          for j := 0 to DataStringGrid.ColCount - 1 do
            DataStringGrid.Cells[j, i + 1] := TempGrid.Cells[j, k];
        end;
      end;

      // Update the display grid
      UpdateDisplayGrid;
    finally
      SortList.Free;
    end;
  finally
    TempGrid.Free;
  end;
end;

procedure TTMDBClientForm.GridViewSelection(Sender: TObject; aCol, aRow: Integer);
var
  Base64Str: string;
begin
  if aRow = 0 then Exit;
  // Retrieve the small poster base64 data from DataStringGrid (column 6).
  Base64Str := DataStringGrid.Cells[6, aRow];
  if Base64Str <> '' then
    LoadImageFromBase64(Base64Str);
end;

procedure TTMDBClientForm.LoadSearchResults(const AJsonStr: string);
var
  JSONData: TJSONData;
  JSONArray: TJSONArray;
  i, RowIndex: Integer;
begin
  try
    JSONData := GetJSON(AJsonStr);
    if JSONData.JSONType <> jtArray then
      raise Exception.Create('Expected a JSON array.');
    JSONArray := TJSONArray(JSONData);

    // Populate DataStringGrid with the full JSON data.
    DataStringGrid.Columns.Clear;
    DataStringGrid.AutoFillColumns := False;
    DataStringGrid.RowCount := 1;
    DataStringGrid.FixedRows := 1;
    with DataStringGrid.Columns.Add do
      Title.Caption := 'Type';
    with DataStringGrid.Columns.Add do
      Title.Caption := 'Released';
    with DataStringGrid.Columns.Add do
      Title.Caption := 'Title';
    with DataStringGrid.Columns.Add do
      Title.Caption := 'id';
    with DataStringGrid.Columns.Add do
      Title.Caption := 'original_title';
    with DataStringGrid.Columns.Add do
      Title.Caption := 'overview';
    with DataStringGrid.Columns.Add do
      Title.Caption := 'small_poster_base64';
    with DataStringGrid.Columns.Add do
      Title.Caption := 'large_poster_link';

    DataStringGrid.RowCount := JSONArray.Count + 1;
    // Optionally, set header cells here if desired.

    for i := 0 to JSONArray.Count - 1 do
    begin
      RowIndex := i + 1; // row 0 is header.
      with JSONArray.Objects[i] do
      begin
        DataStringGrid.Cells[0, RowIndex] := FindPath('type').AsString;
        DataStringGrid.Cells[1, RowIndex] := FindPath('release_date').AsString;
        DataStringGrid.Cells[2, RowIndex] := FindPath('full_title').AsString;
        DataStringGrid.Cells[3, RowIndex] := FindPath('id').AsString;
        DataStringGrid.Cells[4, RowIndex] := FindPath('original_title').AsString;
        DataStringGrid.Cells[5, RowIndex] := FindPath('overview').AsString;
        DataStringGrid.Cells[6, RowIndex] := FindPath('small_poster_base64').AsString;
        DataStringGrid.Cells[7, RowIndex] := FindPath('large_poster_link').AsString;
      end;
    end;

    JSONData.Free;

    // Update the display grid so it reflects the new data.
    UpdateDisplayGrid;
  except
    on E: Exception do
      ShowMessage('Error loading search results: ' + E.Message);
  end;
end;

procedure TTMDBClientForm.LoadImageFromBase64(const Base64Str: string);
var
  Base64Stream: TStringStream;
  DecodingStream: TBase64DecodingStream;
  MS: TMemoryStream;
  Pic: TPicture;
begin
  if Base64Str = '' then Exit;
  Base64Stream := TStringStream.Create(Base64Str);
  try
    DecodingStream := TBase64DecodingStream.Create(Base64Stream, bdmMIME);
    try
      MS := TMemoryStream.Create;
      try
        MS.CopyFrom(DecodingStream, DecodingStream.Size);
        MS.Position := 0;
        Pic := TPicture.Create;
        try
          MS.Position := 0;
          Pic.LoadFromStream(MS);
          SmallPoster.Picture.Assign(Pic);
        finally
          Pic.Free;
        end;
      finally
        MS.Free;
      end;
    finally
      DecodingStream.Free;
    end;
  finally
    Base64Stream.Free;
  end;
end;

end.
