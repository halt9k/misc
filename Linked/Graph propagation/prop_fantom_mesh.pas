unit fantom_mesh;

interface

uses
	System.Classes, System.Types,
	Generics.Collections,
	glob_light,
	glob_gl, U3Dpolys, gl_mesh;

{$I common\defs.inc}
{$I common\autodefs.inc}
{$IFDEF FANTOMS_USE_3D}

type

	TFantomMesh = class(TEntity)
		private const
			FPropagateDepth = 4;

		private type
			TGLMeshList = TObjectList<TGLMesh>;


			TGLMeshListHelper = class helper for TGLMeshList
				public
					class procedure Copy(var Dest: TGLMeshList; const Src: TGLMeshList);
			end;

		private
			FDrawTranslucentAsOpaque                 : Boolean;
			FMeshList                                : TGLMeshList;
			FTransparentList                         : TGLMeshList;
			FSilhouette                              : Boolean;
			FFantomHighlights, FFantomHighlightsCache: TFantomHighlights;
			FbZonesUpdateStarted                     : Boolean;
			FbSmoothEnabled                          : Boolean;
			FbOutlineEnabled                         : Boolean;
			FbForceUpdateCache                       : Boolean;
			FMeshResName                             : string;

			procedure PreCalcMeshColorPatterns(bSupportOutline, bSupportSmooth: Boolean);
			procedure AssignMaskColors;
			procedure AssignSilhouetteColors;


		public
			function GetZoneCount: Integer;
			constructor Create;
			procedure LoadFromRes(const MeshResName: string);
			procedure Assign(Source: TPersistent); override;
			destructor Destroy; override;
			procedure ZonesUpdateBegin;
			procedure ZoneUpdate(Zone: Integer; Color: TColor; bSolid: Boolean = False);
			procedure ZonesUpdateEnd;
			procedure Redraw; override;
			procedure RedrawMasked; override;
			function GetMaskZone(const cl: TGLColor): Integer;

			// function GetClickZone(pt: TPoint): Integer;
			function ShowVertexDebugInfo(const pt: TPoint): TPoint;

			procedure GLBind; override;
			procedure GLRelease; override;

			property  Silhouette: Boolean
				read  FSilhouette
				write FSilhouette;
			property  DrawTranslucentAsOpaque: Boolean
				read  FDrawTranslucentAsOpaque
				write FDrawTranslucentAsOpaque;
			property  ZoneCount: Integer
				read  GetZoneCount;
	end;

{$ENDIF}

implementation

{$IFDEF FANTOMS_USE_3D}

uses

	Winapi.Windows,
	System.SysUtils, Vcl.Controls,
	System.Math,

	DglOpenGL,

	baseio_preferences,
	glob_vcl;

{ TGLMeshListHelper }


class procedure TFantomMesh.TGLMeshListHelper.Copy(var Dest: TGLMeshList;
	const Src: TGLMeshList);
var
	SrcMesh, CloneMesh: TGLMesh;
begin
	FreeAndNil(Dest);
	if not Assigned(Src) then
		Exit;

	Dest := TFantomMesh.TGLMeshList.Create;
	for SrcMesh in Src do begin
		CloneMesh := TGLMesh.Create;
		CloneMesh.Assign(SrcMesh);
		Dest.Add(CloneMesh);
	end;
end;

{ TFantomMesh }


procedure TFantomMesh.LoadFromRes(const MeshResName: string);

	procedure LoadFromStream(var ResStream: TResourceStream);
	var
		meshNum   : Integer;
		sign      : cardinal;
		atEnd     : Boolean;
		Mesh      : TGLMesh;
		effBytes  : Byte;
		effectsSet: TMeshEffectsSet;
	begin
		atEnd := False;

		ResStream.Read(sign, sizeof(sign));
		if sign <> $46414E54 then begin // FANT
			Assert(False);
			Exit;
		end;
		ResStream.Read(sign, sizeof(sign));
		if sign <> $4E455854 then begin // NEXT
			Assert(False);
			Exit;
		end;

		ResStream.Read(effBytes, sizeof(effBytes));
		effectsSet := TMeshEffectsSet(effBytes);
		FbSmoothEnabled := meSMOOTH in effectsSet;
		FbOutlineEnabled := meOUTLINED in effectsSet;


		while not atEnd do begin
			ResStream.Read(sign, sizeof(sign));
			if sign <> $4E455854 then begin
				Assert(False);
				Exit;
			end;

			ResStream.Read(sign, sizeof(sign));
			case sign of
				$4E4F4E45: atEnd := true; // NONE
				$5A4F4E45: begin
					ResStream.Read(sign, sizeof(sign)); // zone number
					meshNum := sign;

					Mesh := TGLMesh.Create;
					try
						Mesh.LoadFromStream(ResStream);
					except
						FreeAndNil(Mesh);
						Assert(False);
					end;

					// mesh.CalcNormals; {= broken zone seals}

					if meshNum = 0 then
						FTransparentList.Add(Mesh)
					else
						FMeshList.Add(Mesh);
				end;
				else Assert(False);
			end;
		end;
	end;

	procedure Scale;
	var
		Mesh   : TGLMesh;
		MaxDist: Single;
	begin
		MaxDist := 0;
		for Mesh in FMeshList do
			MaxDist := max(MaxDist, Mesh.MaxSize);
		for Mesh in FTransparentList do
			MaxDist := max(MaxDist, Mesh.MaxSize);

		if MaxDist > 0 then begin
			for Mesh in FMeshList do
				Mesh.Scale(1.0 / MaxDist);

			for Mesh in FTransparentList do
				Mesh.Scale(1.0 / MaxDist);
		end;
	end;


var
	ResStream: TResourceStream;
begin
	FMeshResName := MeshResName;
	try
		ResStream := TResourceStream.Create(HInstance, MeshResName, PChar(12821));
		try
			LoadFromStream(ResStream);
		finally
			FreeAndNil(ResStream);
		end;
	except
		raise;
	end;
	Scale;
	AssignMaskColors;
	AssignSilhouetteColors;

	PreCalcMeshColorPatterns(FbOutlineEnabled, FbSmoothEnabled);
end;


destructor TFantomMesh.Destroy;
begin
	FreeAndNil(FMeshList);
	FreeAndNil(FTransparentList);
	inherited Destroy;
end;


procedure TFantomMesh.Assign(Source: TPersistent);
var
	S: TFantomMesh;
begin
	inherited;
	if Source is TFantomMesh then begin
		S := TFantomMesh(Source);
		FDrawTranslucentAsOpaque := S.FDrawTranslucentAsOpaque;
		FbSmoothEnabled := S.FbSmoothEnabled;
		FbOutlineEnabled := S.FbOutlineEnabled;
		FSilhouette := S.FSilhouette;

		TGLMeshList.Copy(FMeshList, S.FMeshList);
		TGLMeshList.Copy(FTransparentList, S.FTransparentList);

		FFantomHighlights := Copy(S.FFantomHighlights);
		FFantomHighlightsCache := Copy(S.FFantomHighlightsCache);

		FbZonesUpdateStarted := S.FbZonesUpdateStarted;
		FbForceUpdateCache := S.FbForceUpdateCache;
		FMeshResName := S.FMeshResName;
	end;
end;


procedure TFantomMesh.AssignMaskColors;
var
	i   : Integer;
	Mesh: TGLMesh;
	cl  : TGLColor;
begin
	for i := 0 to FMeshList.Count - 1 do begin
		Mesh := FMeshList[i];
		cl.V := i * 10;
		Mesh.SetMaskColor(cl);
	end;
end;


procedure TFantomMesh.AssignSilhouetteColors;
var
	Mesh: TGLMesh;
begin
	for Mesh in FTransparentList do
		Mesh.SetSolidVertexColors(clSilhouette);
end;


constructor TFantomMesh.Create;
begin
	inherited;

	FDrawTranslucentAsOpaque := False;
	FbSmoothEnabled := False;
	FbOutlineEnabled := False;
	FFantomHighlights := nil;
	FFantomHighlightsCache := nil;

	// FHighlightsDict := THighlights.Create;
	FMeshList := TGLMeshList.Create;
	FTransparentList := TGLMeshList.Create;

	FMeshResName := '';
end;


function TFantomMesh.GetMaskZone(const cl: TGLColor): Integer;
begin
	Result := cl.V div 10;
end;


procedure TFantomMesh.PreCalcMeshColorPatterns(bSupportOutline, bSupportSmooth: Boolean);
var
	i, j       : Integer;
	FntFillInfo: TFantomFillInfo;
begin
	if not bSupportOutline and not bSupportSmooth then
		Exit;

	FntFillInfo := nil;
	SetLength(FntFillInfo, FMeshList.Count);

	// Add inner weight
	for i := 0 to FMeshList.Count - 1 do begin
		FMeshList[i].CalculateBoundingShape;
		FMeshList[i].FillPrepVertices(i, FntFillInfo[i].Verts);
	end;


	// Create cross mesh links, excluding self-self
	for i := 0 to FMeshList.Count - 1 do
		for j := 0 to i - 1 do begin
			if FMeshList[i].HasIntersects(FMeshList[j],
				AppPrefs.FantomsGraphics.SmoothingMaxRange) then begin
				FMeshList[i].FillDetectCrossLinks(i, j, FMeshList[i], FMeshList[j],
					FntFillInfo[i], FntFillInfo[j],
					AppPrefs.FantomsGraphics.SmoothingMaxRange);
			end;

		end;

	if bSupportSmooth then begin
		// Propagate inner links & crosslinks
		for j := 0 to FPropagateDepth - 1 do begin
			for i := 0 to FMeshList.Count - 1 do
				FMeshList[i].FillPropagateInner(FntFillInfo[i].Verts);
			for i := 0 to FMeshList.Count - 1 do
				FMeshList[i].FillPropagateCross(FntFillInfo, i);
		end;

		// Finally calculate weights of links
		for i := 0 to FMeshList.Count - 1 do
			FMeshList[i].FillEstimateWeights(FntFillInfo[i].Verts);
	end;


	// And detect edges for segment fantoms
	if bSupportOutline then begin
		for i := 0 to FMeshList.Count - 1 do
			FMeshList[i].FillDetectEdges(FntFillInfo[i]);
	end;

	// Set propagated links to meshes
	for i := 0 to FMeshList.Count - 1 do begin
		FMeshList[i].FillSet(FntFillInfo[i], bSupportOutline, bSupportSmooth);
	end;
end;


procedure TFantomMesh.ZonesUpdateBegin;
var
	i: Integer;
begin
	Assert(not FbZonesUpdateStarted);
	// FHighlightsDict.Clear;
	FbZonesUpdateStarted := true;
	SetLength(FFantomHighlights, FMeshList.Count);
	for i := 0 to high(FFantomHighlights) do begin
		FFantomHighlights[i].bSolid := true;
		FFantomHighlights[i].Color := clMeshDefault;
	end;

end;


procedure TFantomMesh.ZoneUpdate(Zone: Integer; Color: TColor; bSolid: Boolean = False);
var
	R, G, B  : Byte;
	HighLight: TMeshHighlight;
begin
	Assert(InRange(Zone, 0, FMeshList.Count - 1));
	Assert(FbZonesUpdateStarted);

	R := GetRValue(Color);
	G := GetGValue(Color);
	B := GetBValue(Color);

	// Highlight matches background
	if FMeshList[Zone].bTransparent and (R + G + B > 240 * 3) then
		HighLight.Color := clMeshDefault
	else
		HighLight.Color.V := Color;
	HighLight.bSolid := bSolid;

	FFantomHighlights[Zone] := HighLight;
end;


procedure TFantomMesh.ZonesUpdateEnd;
var
	Zone: Integer;
	sz  : Integer;
begin
	if FbZonesUpdateStarted then
		FbZonesUpdateStarted := False
	else
		Assert(False);


	sz := sizeof(TMeshHighlight) * Length(FFantomHighlights);
	if Length(FFantomHighlightsCache) = Length(FFantomHighlights) then
		if CompareMem(FFantomHighlightsCache, FFantomHighlights, sz) then
			if not FbForceUpdateCache then
				Exit
			else
				FbForceUpdateCache := False;

	for Zone := 0 to high(FFantomHighlights) do
		if AppPrefs.FantomsGraphics.UseSmoothing and FbSmoothEnabled and
			(not FFantomHighlights[Zone].bSolid) then
			FMeshList[Zone].SetSmoothVertexColors(FFantomHighlights,
				not AppPrefs.FantomsGraphics.DebugShowWire)
		else
			FMeshList[Zone].SetSolidVertexColors(FFantomHighlights[Zone].Color);

	FFantomHighlightsCache := Copy(FFantomHighlights);
end;


function TFantomMesh.GetZoneCount: Integer;
begin
	Result := FMeshList.Count;
end;


procedure TFantomMesh.Redraw;
type
	TMeshDesc = (mdTRANSPARENTS, mdSOLIDS);

	procedure DrawSilhouette;
	var
		TrMesh: TGLMesh;
	begin
		for TrMesh in FTransparentList do begin
			TrMesh.SetColorMode(cmSILHOUETTE);
			TrMesh.Redraw;
		end;
	end;

	procedure DrawMeshes(ToDraw: TMeshDesc);
	var
		Mesh: TGLMesh;
	begin
		for Mesh in FMeshList do begin
			if (ToDraw = mdSOLIDS) and Mesh.bTransparent then
				continue;
			if (ToDraw = mdTRANSPARENTS) and not Mesh.bTransparent then
				continue;

			if (ToDraw = mdSOLIDS) then
				Mesh.SetColorMode(cmNORMAL);

			if (ToDraw = mdTRANSPARENTS) then
				Mesh.SetColorMode(cmINVERTED);

			glPolygonMode(GL_FRONT_AND_BACK, GL_FILL);
			Mesh.Redraw;

			if AppPrefs.FantomsGraphics.DebugShowWire then begin
				glPolygonMode(GL_FRONT_AND_BACK, GL_LINE);
				Mesh.SetColorMode(cmINVERTED);
				Mesh.Redraw;
			end;
		end;

	end;


begin

	// glDisable(GL_CULL_FACE); //Some model bug requres this
	// glCullFace(GL_FRONT);

	glBlendFunc(GL_ZERO, GL_ONE_MINUS_SRC_COLOR);

	glDisable(GL_BLEND);

	DrawMeshes(mdSOLIDS);

	glEnable(GL_BLEND);
	glDepthMask(GL_FALSE);

	DrawMeshes(mdTRANSPARENTS);

	if FSilhouette then
		DrawSilhouette;

	glDepthMask(GL_TRUE);
end;


procedure TFantomMesh.RedrawMasked;
var
	Mesh: TGLMesh;
begin
	glDisable(GL_BLEND);
	glDisable(GL_LIGHTING);

	for Mesh in FMeshList do
		Mesh.Redraw(true);

	glEnable(GL_LIGHTING);
	glEnable(GL_BLEND);
end;


procedure TFantomMesh.GLBind;
var
	Mesh: TGLMesh;
begin
	for Mesh in FMeshList do
		Mesh.CreateVertexBuffers;
	for Mesh in FTransparentList do
		Mesh.CreateVertexBuffers;
end;


procedure TFantomMesh.GLRelease;
var
	Mesh: TGLMesh;
begin
	for Mesh in FMeshList do
		Mesh.FreeVertexBuffers;
end;


function TFantomMesh.ShowVertexDebugInfo(const pt: TPoint): TPoint;
var
	Mesh                      : TGLMesh;
	MinInfo, MinInfo2, CurInfo: TVertexDebugInfo;
	msg                       : string;
	i                         : Integer;
	lnk                       : TVertexLink;
	Zone, Zone2               : Integer;
begin
	FbForceUpdateCache := true;

	Zone := 0;
	Zone2 := 0;

	MinInfo.HitLength := MaxSingle;
	MinInfo2.HitLength := MaxSingle;
	MinInfo.Links := nil;
	MinInfo2.Links := nil;
	for i := 0 to FMeshList.Count - 1 do begin
		Mesh := FMeshList[i];
		// if AppTmpPrefs.Show3DDebugHint then begin
		CurInfo := Mesh.DebugGetScreenVertexInfo(pt.x, pt.y);
		if MinInfo.HitLength > CurInfo.HitLength then begin
			MinInfo := CurInfo;
			Zone := i;
		end else if MinInfo2.HitLength > CurInfo.HitLength then begin
			MinInfo2 := CurInfo;
			Zone2 := i;
		end;
	end;


	msg := FormatAms('SrcZone %d id %d', [Zone, MinInfo.id]) + sLineBreak;
	msg := msg + FormatAms('Pos %5.3f %5.3f %5.3f Length %4.1f',
		[MinInfo.Pos.x, MinInfo.Pos.y, MinInfo.Pos.Z, MinInfo.HitLength]) + sLineBreak;
	if Assigned(MinInfo.Links) then
		for lnk in MinInfo.Links do
			msg := msg + FormatAms('Target zone %d id %d length %6.4f weight %6.4f',
				[lnk.Zone, lnk.id, lnk.Length, lnk.Weight]) + sLineBreak;
	if true then begin
		msg := msg + sLineBreak + sLineBreak;
		msg := msg + FormatAms('SrcZone %d id %d', [Zone2, MinInfo2.id]) + sLineBreak;
		msg := msg + FormatAms('Pos %5.3f %5.3f %5.3f Length %4.1f',
			[MinInfo2.Pos.x, MinInfo2.Pos.y, MinInfo2.Pos.Z, MinInfo2.HitLength]) +
			sLineBreak;
		if Assigned(MinInfo2.Links) then
			for lnk in MinInfo2.Links do
				msg := msg + FormatAms('Target zone %d id %d length %6.4f weight %6.4f',
					[lnk.Zone, lnk.id, lnk.Length, lnk.Weight]) + sLineBreak;

	end;
	ShowUniqueHint(msg, Mouse.CursorPos + TPoint.Create(200, 0));

	Result.x := MinInfo.ScreenPos.x;
	Result.y := MinInfo.ScreenPos.y;
end;


{$ENDIF}

end.
