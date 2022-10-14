unit gl_mesh;

{$WARN UNSAFE_CODE OFF}

interface

uses
	System.Classes, System.Types,
	System.Math, {Math for inline}
	System.Math.Vectors,
	glob_gl;

type
	TMeshColorMode = (cmNORMAL, cmINVERTED, cmSILHOUETTE);
	TMeshEffects = (meSMOOTH = 1, meOUTLINED = 2);
	TMeshEffectsSet = set of TMeshEffects;

	GLuint = Cardinal;
	GLfloat = Single;


	TBounds = record
		SphCenter: TPoint3D;
		SphRadius: Single;
		BoxMax, BoxMin: TPoint3D;
		function Includes(const B: TBounds): Boolean;
	end;


	TVertexLink = record
		Zone, Id: Integer;
		Pos: TPoint3D;
		Length, MaxLength, Weight: Single;
	end;


	PVertexLink = ^TVertexLink;
	// If perfomance will be problem again (all feautures reenabled),
	// consider switch back to TList<TVertexLink>
	// TVertexLinks = TList<TVertexLink>;
	TVertexLinks = TArray<TVertexLink>;
	PVertexLinks = ^TVertexLinks;


	TVertexDebugInfo = record
		ScreenPos: TPoint;
		Pos: TPoint3D;
		Id: Integer;
		HitLength, HitLength2: Single;
		Links: TVertexLinks;
	end;


	TVertexInfo = record
		RigidLinksCount: Integer;
		PropagatedLinksCount: Integer;
		FillLinks: TVertexLinks;
		SelfLink: TVertexLink;
		procedure AddLink(const ALink: TVertexLink; IsHardLink: Boolean);
	end;


	PVertexInfo = ^TVertexInfo;
	TVertexInfos = TArray<TVertexInfo>;
	PVertexInfos = ^TVertexInfos;


	TGLEdge = record
		Id1, Id2: GLuint;
	end;


	TEdgeInfos = TArray<TGLEdge>;
	PEdgeInfos = ^TEdgeInfos;


	TZoneFillInfo = record
		public
			Verts          : TVertexInfos;
			CrossEdgesIndex: TEdgeInfos;
			procedure Assign(Source: TZoneFillInfo);
	end;


	TFantomFillInfo = TArray<TZoneFillInfo>;


	TGLMesh = class(TPersistent)
		public
			bTransparent: Boolean;
			VertexCount : Integer;
			FacesCount  : Integer;
			fExtent     : GLfloat;
			Bounds      : TBounds;

			constructor Create;
			destructor Destroy; override;
			procedure LoadFromStream(AStream: TStream);
			procedure LoadFromFile(const FileName: string);
			procedure CalcNormals;
			procedure Assign(Source: TPersistent); override;
			procedure Redraw(bMaskOnly: Boolean = False);
			procedure SetSmoothVertexColors(const ArrHighlights: TFantomHighlights;
				bDebug: Boolean);
			procedure SetSolidVertexColors(const AColor: TGLColor);
			procedure SetMaskColor(const AColor: TGLColor);
			procedure SetColorMode(AMode: TMeshColorMode);


			procedure Scale(Factor: Single);
			function MaxSize: Single;
			procedure FillPrepVertices(AZone: Integer; var FillInfo: TVertexInfos);
			procedure FillEstimateWeights(var FillInfo: TVertexInfos);
			procedure FillDetectEdges(var FillInfo: TZoneFillInfo);
			procedure FillDetectCrossLinks(ZoneA, ZoneB: Integer;
				const MeshA, MeshB: TGLMesh; var FillA, FillB: TZoneFillInfo;
				ARangeThresholdPercent: Single);
			procedure FillSet(const fi: TZoneFillInfo;
				bSupportOutline, bSupportSmooth: Boolean);
			procedure FillPropagateInner(var FillInfo: TVertexInfos);
			procedure FillPropagateCross(var FillInfos: TFantomFillInfo;
				CurMesh: Integer);

			function HasIntersects(const AMesh: TGLMesh; Gap: Single): Boolean;
			procedure CalculateBoundingShape;
			function DebugGetScreenVertexInfo(ScrX, ScrY: Integer): TVertexDebugInfo;

			procedure CreateVertexBuffers;
			procedure FreeVertexBuffers;

		type
			TGLFace = record
				Id1, Id2, Id3: GLuint;
			end;


			PGLFace = ^TGLFace;
			TGLFacesArray = array of TGLFace;
			PGLFacesArray = ^TGLFacesArray;
			TGLColorArray = array of TGLColor;
			PGLColorArray = ^TGLColorArray;
			TPoint3DArray = array of TPoint3D;
			PPoint3DArray = ^TPoint3DArray;


			{ TAvgColorSum = record
			  RSum, GSum, BSum: Single;
			  WSum: Single;
			  end; }

		protected
			FFaces   : TGLFacesArray;
			FVertices: TPoint3DArray;

			FFasetNormals : TPoint3DArray;
			FSmoothNormals: TPoint3DArray;

			FRawColors: TGLColorArray;
			FColors   : TGLColorArray;

			FColorMode: TMeshColorMode;
			FFillInfo : TZoneFillInfo;

			FGLVertexBuffer    : GLuint;
			FGLFacesIndexBuffer: GLuint;
			FGLCrossEdgesBuffer: GLuint;
			FGLNormalBuffer    : GLuint;
			FGLColorsBuffer    : GLuint;

		private
			FclMaskColor: TGLColor;
			FbSmoothed  : Boolean;
			FbOutlined  : Boolean;

			FGLSettings : TGLSettingsSwitcher;
			FGLValidator: TGLContextValidator;
			procedure ApplyColorMode;
	end;

implementation

uses
	DglOpenGL,
	System.SysUtils,
	System.Generics.Collections;


procedure TGLMesh.CalcNormals;
var
	i                                 : Integer;
	wrki, vx1, vy1, vz1, vx2, vy2, vz2: GLfloat;
	nx, ny, nz                        : GLfloat;
	wrkVector                         : TPoint3D;
	wrkVector1, wrkVector2, wrkVector3: TPoint3D;
	wrkFace                           : TGLFace;
begin

	for i := 0 to FacesCount - 1 do begin
		wrkFace := FFaces[i];
		wrkVector1 := FVertices[wrkFace.Id1];
		wrkVector2 := FVertices[wrkFace.Id2];
		wrkVector3 := FVertices[wrkFace.Id3];

		vx1 := wrkVector1.x - wrkVector2.x;
		vy1 := wrkVector1.y - wrkVector2.y;
		vz1 := wrkVector1.z * fExtent - wrkVector2.z * fExtent;

		vx2 := wrkVector2.x - wrkVector3.x;
		vy2 := wrkVector2.y - wrkVector3.y;
		vz2 := wrkVector2.z - wrkVector3.z;

		nx := vy1 * vz2 - vz1 * vy2;
		ny := vz1 * vx2 - vx1 * vz2;
		nz := vx1 * vy2 - vy1 * vx2;

		wrki := sqrt(nx * nx + ny * ny + nz * nz);
		if wrki = 0 then
			wrki := 1;

		wrkVector.x := nx / wrki;
		wrkVector.y := ny / wrki;
		wrkVector.z := nz / wrki;

		FFasetNormals[i] := wrkVector;
	end;
end;


// function used in separate gms viewer


procedure TGLMesh.LoadFromFile(const FileName: string);
var
	f      : TextFile;
	S      : string;
	i      : Integer;
	Vertex : TPoint3D;
	Normal : TPoint3D;
	SNormal: TPoint3D;
	Face   : TGLFace;
begin
	AssignFile(f, FileName);
	Reset(f);
	repeat
		ReadLn(f, S);
	until (S = 'numverts numfaces') or eof(f);
	ReadLn(f, VertexCount, FacesCount);

	SetLength(FVertices, VertexCount);
	SetLength(FSmoothNormals, VertexCount);
	SetLength(FFaces, FacesCount);
	SetLength(FFasetNormals, FacesCount);

	ReadLn(f, S); // stroka Mesh vertices:

	for i := 0 to VertexCount - 1 do begin
		ReadLn(f, Vertex.x, Vertex.y, Vertex.z);

		FVertices[i] := Vertex;
	end;

	// TODO 4 What for fnom was here? Func not used in main app
	// if (fnom < 13) and (pos('pozv', FileName) <> 0) then
	if (Pos('pozv', FileName) <> 0) then
		for i := 0 to VertexCount - 1 do
			FVertices[i].y := FVertices[i].y + 0.15;
	ReadLn(f, S); // stroka end vertices
	ReadLn(f, S); // stroka Mesh faces:

	for i := 0 to FacesCount - 1 do begin
		ReadLn(f, Face.Id1, Face.Id2, Face.Id3);
		Dec(Face.Id1);
		Dec(Face.Id2);
		Dec(Face.Id3);
		FFaces[i] := Face;
	end;

	ReadLn(f, S); // stroka end faces
	ReadLn(f, S); // stroka Faset normals:

	for i := 0 to FacesCount - 1 do begin
		ReadLn(f, Normal.x, Normal.y, Normal.z);
		FFasetNormals[i] := Normal;
	end;

	ReadLn(f, S); // stroka end faset normals
	ReadLn(f, S); // stroka Smooth normals:

	for i := 0 to VertexCount - 1 do begin
		ReadLn(f, SNormal.x, SNormal.y, SNormal.z);
		FSmoothNormals[i] := SNormal;
	end;

	CloseFile(f);
end;


function TBounds.Includes(const B: TBounds): Boolean;
var
	bX, bY, bZ, bS: Boolean;
begin
	bX := (B.BoxMin.x > BoxMin.x) and (B.BoxMax.x < BoxMax.x);
	bY := (B.BoxMin.y > BoxMin.y) and (B.BoxMax.y < BoxMax.y);
	bZ := (B.BoxMin.z > BoxMin.z) and (B.BoxMax.z < BoxMax.z);
	bS := ((B.SphCenter - SphCenter).Length + B.SphRadius < SphRadius);
	Result := bX and bY and bZ and bS;
end;


procedure TVertexInfo.AddLink(const ALink: TVertexLink; IsHardLink: Boolean);
var
	LId, LinkLen: Integer;
	NewLen      : Single;
begin
	NewLen := (ALink.Pos - SelfLink.Pos).Length;

	if (ALink.MaxLength > 0) and (NewLen > ALink.MaxLength) then
		Exit;

	// Assert(ALink.Zone <> SelfLink.Zone);

	if Assigned(FillLinks) then
		for LId := 0 to Length(FillLinks) - 1 do
			if FillLinks[LId].Zone = ALink.Zone then begin
				if FillLinks[LId].Length > NewLen then begin
					FillLinks[LId] := ALink;
					FillLinks[LId].Length := NewLen;
					PropagatedLinksCount := min(LId, PropagatedLinksCount);
				end;
				Exit
			end;

	LinkLen := Length(FillLinks);
	SetLength(FillLinks, LinkLen + 1);
	FillLinks[LinkLen] := ALink;
	FillLinks[LinkLen].Length := NewLen;

	if IsHardLink then
		Inc(RigidLinksCount)
end;


procedure TGLMesh.FillSet(const fi: TZoneFillInfo;
	bSupportOutline, bSupportSmooth: Boolean);
begin
	FbSmoothed := bSupportSmooth;
	FbOutlined := bSupportOutline;

	Assert(Length(fi.Verts) = VertexCount);
	FFillInfo := fi;
end;


procedure TGLMesh.FillPrepVertices(AZone: Integer; var FillInfo: TVertexInfos);
var
	i: Integer;
begin
	SetLength(FillInfo, VertexCount);
	for i := 0 to VertexCount - 1 do
		with FillInfo[i] do begin
			SelfLink.Zone := AZone;
			SelfLink.Id := i;
			SelfLink.Length := 0;
			SelfLink.Weight := 1;
			SelfLink.Pos := FVertices[i];
			RigidLinksCount := 0;
			PropagatedLinksCount := 0;
			FillLinks := nil; // TVertexLinkArray.Create;
		end;
end;


// procedure TGLMesh.FillEstimateWeights(AZone: Integer; var FillInfo: TVertexInfos);
procedure TGLMesh.FillEstimateWeights(var FillInfo: TVertexInfos);
var
	i, j: Integer;
	pl  : PVertexInfo;

begin
	for i := 0 to VertexCount - 1 do begin
		pl := @FillInfo[i];
		if Assigned(pl.FillLinks) then
			for j := 0 to Length(pl.FillLinks) - 1 do
				with pl.FillLinks[j] do begin
					// self link, l = -1, w = 1
					// rigid link, l > 0, w = 1
					// cross link, len > 0, w < 1
					// Links[id].Weight := exp( -Sqr(MinRange * exp(1) / PassRng));

					// Weight := exp( -Sqr(Length * exp(1) / ZoneRadiuses[Zone]))
					// but must be linear?!
					// if j < FillInfo[i].RigidLinksCount then
					// Weight := 1
					// else
					Weight := max(MaxLength - Length, 0) / MaxLength;
				end;
	end;
end;


procedure TGLMesh.FillPropagateInner(var FillInfo: TVertexInfos);
	procedure PropInnerLink(var v1, v2: TVertexInfo);
	var
		lnk1, lnk2: PVertexLink;
		i, j      : Integer;
	begin
		// at this point contains self link and RigidLinks count of crosslinks

		if Assigned(v1.FillLinks) then begin
			for i := v1.PropagatedLinksCount to Length(v1.FillLinks) - 1 do begin
				lnk1 := @v1.FillLinks[i];
				v2.AddLink(lnk1^, False);
			end;
		end;

		if Assigned(v2.FillLinks) then begin
			for j := v2.PropagatedLinksCount to Length(v2.FillLinks) - 1 do begin
				lnk2 := @v2.FillLinks[j];
				v1.AddLink(lnk2^, False);
			end;
		end;
	end;


var
	i         : Integer;
	v1, v2, v3: Integer;
begin
	// any edge detection seems to be more costly than
	// double firing same links (v2->v1 & v1->v2 + v1->v2 & v2->v1)
	// very fast edge detection was created anyway with FillDetectEdges, in case of bad perfomance
	// try to use detected edges here to reduce twice this stage requrements
	for i := 0 to FacesCount - 1 do begin
		v1 := FFaces[i].Id1;
		v2 := FFaces[i].Id2;
		v3 := FFaces[i].Id3;
		PropInnerLink(FillInfo[v1], FillInfo[v2]);
		PropInnerLink(FillInfo[v2], FillInfo[v3]);
		PropInnerLink(FillInfo[v3], FillInfo[v1]);
	end;
end;


procedure TGLMesh.FillDetectEdges(var FillInfo: TZoneFillInfo);
var
	len   : Integer;
	PEdges: PEdgeInfos;

	procedure TestAdd(const v1, v2: Integer; const p1, p2: PVertexInfo);
	var
		j, k  : Integer;
		l1, l2: PVertexLink;
	begin
		for j := 0 to p1.RigidLinksCount - 1 do begin
			for k := 0 to p2.RigidLinksCount - 1 do begin
				l1 := @p1.FillLinks[j];
				l2 := @p2.FillLinks[k];

				if (l1.Length + l2.Length) > 0 then
					Continue;

				if l1.Zone = l2.Zone then begin
					PEdges^[len].Id1 := v1;
					PEdges^[len].Id2 := v2;
					Inc(len);
					Exit;
				end;
			end;
		end;
	end;

	procedure FilterEdges(var EdgeList: TList<Integer>);
	var
		v1, v2, v3: Integer;
		i         : Integer;
		UniqueList: TList<Integer>;
	begin
		for i := 0 to FacesCount - 1 do begin
			v1 := FFaces[i].Id1;
			v2 := FFaces[i].Id2;
			v3 := FFaces[i].Id3;
			if v1 > v3 then
				TGeneric.Swap(v1, v3);
			if v1 > v2 then
				TGeneric.Swap(v1, v2);
			if v2 > v3 then
				TGeneric.Swap(v2, v3);
			// v3 > v2 > v1
			EdgeList.Add(v2 * VertexCount + v1);
			EdgeList.Add(v3 * VertexCount + v2);
			EdgeList.Add(v3 * VertexCount + v1);
		end;
		// To skip duplicate edges
		EdgeList.Sort;

		UniqueList := TList<Integer>.Create;
		try
			EdgeList.Add( -1);
			EdgeList.Insert(0, -1);
			for i := 1 to EdgeList.Count - 2 do begin
				if (EdgeList[i] <> EdgeList[i - 1]) and (EdgeList[i] <> EdgeList[i + 1])
				then
					UniqueList.Add(EdgeList[i]);
			end;

		finally
			TGeneric.Swap(UniqueList, EdgeList);
			FreeAndNil(UniqueList);
		end;
	end;

	procedure FilterEdgesExternal(var EdgeList: TList<Integer>);
	var
		i     : Integer;
		v1, v2: Integer;
		r1, r2: Boolean;
		p1, p2: PVertexInfo;
	begin
		PEdges := @FillInfo.CrossEdgesIndex;
		SetLength(PEdges^, FacesCount * 3);
		len := 0;
		for i := 0 to EdgeList.Count - 1 do begin
			v1 := EdgeList[i] div VertexCount;
			v2 := EdgeList[i] mod VertexCount;

			p1 := @FillInfo.Verts[v1];
			p2 := @FillInfo.Verts[v2];
			r1 := (p1.RigidLinksCount > 0);
			r2 := (p2.RigidLinksCount > 0);
			if (r1 and r2) then
				TestAdd(v1, v2, p1, p2);
		end;
		SetLength(PEdges^, len);
	end;


var
	EdgeList: TList<Integer>;
begin
	// Requres both non-internal edge detection and their external connectivity test
	EdgeList := TList<Integer>.Create;
	try
		FilterEdges(EdgeList);
		FilterEdgesExternal(EdgeList);
	finally
		FreeAndNil(EdgeList);
	end;
end;


procedure TGLMesh.FillPropagateCross(var FillInfos: TFantomFillInfo; CurMesh: Integer);

	procedure SyncOuterLinks(const VrtFill: TVertexInfo);
	var
		Id, TgtId, TgtZone, SrcRigidId: Integer;
		SrcLink                       : PVertexLink;
		TgtFill                       : PVertexInfo;
	begin
		// (VrtFill.RigidLinksCount <> TgtFill.RigidLinksCount); if tri-vertex

		for SrcRigidId := 0 to VrtFill.RigidLinksCount - 1 do begin
			SrcLink := @VrtFill.FillLinks[SrcRigidId];
			TgtZone := SrcLink.Zone;
			TgtId := SrcLink.Id;
			TgtFill := @FillInfos[TgtZone].Verts[TgtId];

			for Id := VrtFill.RigidLinksCount to Length(VrtFill.FillLinks) - 1 do begin
				SrcLink := @VrtFill.FillLinks[Id];
				TgtFill.AddLink(SrcLink^, False);
			end;
		end;

	end;


var
	i       : Integer;
	CurVerts: PVertexInfos;

begin
	CurVerts := @FillInfos[CurMesh].Verts;
	for i := 0 to VertexCount - 1 do begin
		SyncOuterLinks(CurVerts^[i]);
		// To prevent repetitions overhead in next propagation
		if Assigned(CurVerts^[i].FillLinks) then
			CurVerts^[i].PropagatedLinksCount := Length(CurVerts^[i].FillLinks) - 1;
	end;
end;


procedure TGLMesh.FillDetectCrossLinks(ZoneA, ZoneB: Integer; const MeshA, MeshB: TGLMesh;
	var FillA, FillB: TZoneFillInfo; ARangeThresholdPercent: Single);

	function FilterVerts(const Mesh: TGLMesh; const Bounds: TBounds): TList<Integer>;
	var
		i          : Integer;
		BMX, BMN, V: TPoint3D;
	begin
		Result := TList<Integer>.Create;

		BMX := Bounds.BoxMax;
		BMN := Bounds.BoxMin;

		// Perfomance sensitive, cleanest way
		for i := 0 to Mesh.VertexCount - 1 do begin
			V := Mesh.FVertices[i];
			if (V.z < BMN.z) or (V.z > BMX.z) then
				Continue;
			if (V.x < BMN.x) or (V.x > BMX.x) then
				Continue;
			if (V.y < BMN.y) or (V.y > BMX.y) then
				Continue;
			if ((V - Bounds.SphCenter).Length > Bounds.SphRadius) then
				Continue;
			Result.Add(i);
		end;
	end;


	procedure CrossLink(i, j: Integer);
	var
		lnkA, lnkB: TVertexLink;
	begin
		lnkA.Zone := ZoneA;
		lnkA.Id := i;
		lnkA.Pos := MeshA.FVertices[i];
		lnkA.Length := 0;
		lnkA.MaxLength := MeshA.Bounds.SphRadius * ARangeThresholdPercent;

		lnkB.Zone := ZoneB;
		lnkB.Id := j;
		lnkB.Pos := MeshB.FVertices[j];
		lnkB.Length := 0;
		lnkB.MaxLength := MeshB.Bounds.SphRadius * ARangeThresholdPercent;

		FillA.Verts[i].AddLink(lnkB, True);
		FillB.Verts[j].AddLink(lnkA, True);
	end;


var
	i, j, IdA, IdB    : Integer;
	IndexesA, IndexesB: TList<Integer>;
	VertsA, VertsB    : TPoint3DArray;
	maxgap            : Single;
begin
	maxgap := ARangeThresholdPercent * 0.1 *
		(MeshA.Bounds.SphRadius + MeshB.Bounds.SphRadius) / 2;

	IndexesA := FilterVerts(MeshA, MeshB.Bounds);
	IndexesB := FilterVerts(MeshB, MeshA.Bounds);
	VertsA := MeshA.FVertices;
	VertsB := MeshB.FVertices;

	try
		// Perfomance sensitive; "for in" much slower
		for i := 0 to IndexesA.Count - 1 do
			for j := 0 to IndexesB.Count - 1 do begin
				IdA := IndexesA.List[i];
				IdB := IndexesB.List[j];

				if Abs(VertsA[IdA].z - VertsB[IdB].z) > maxgap then
					Continue;
				if Abs(VertsA[IdA].y - VertsB[IdB].y) > maxgap then
					Continue;
				if Abs(VertsA[IdA].x - VertsB[IdB].x) > maxgap then
					Continue;

				CrossLink(IdA, IdB);

			end;


	finally
		FreeAndNil(IndexesA);
		FreeAndNil(IndexesB);
	end;
end;


function TGLMesh.MaxSize: Single;
var
	i: Integer;
begin
	Result := 0;
	for i := 0 to VertexCount - 1 do begin
		Result := max(Result, Abs(FVertices[i].x));
		Result := max(Result, Abs(FVertices[i].y));
		Result := max(Result, Abs(FVertices[i].z));
	end;
end;


procedure TGLMesh.Scale(Factor: Single);
var
	j: Integer;
begin
	for j := 0 to VertexCount - 1 do
		FVertices[j] := FVertices[j] * Factor;

	Bounds.SphCenter := Bounds.SphCenter * Factor;
	Bounds.SphRadius := Bounds.SphRadius * Factor;
	Bounds.BoxMax := Bounds.BoxMax * Factor;
	Bounds.BoxMin := Bounds.BoxMin * Factor;

end;


procedure TGLMesh.SetSolidVertexColors(const AColor: TGLColor);
var
	i: Integer;
begin
	for i := 0 to VertexCount - 1 do
		FRawColors[i] := AColor;
	ApplyColorMode;
end;


procedure TGLMesh.SetMaskColor(const AColor: TGLColor);
begin
	FclMaskColor := AColor;
end;


procedure TGLMesh.SetSmoothVertexColors(const ArrHighlights: TFantomHighlights;
	bDebug: Boolean);

	function ValidColor(cl: Single): Boolean; inline;
	begin
		Result := InRange(cl, -0.01, 255.01);
	end;


var
	RSum, GSum, BSum, WSum: Single;
	procedure CalcAddLink(const lnk: TVertexLink);
	var
		zn: Integer;
		w : Single;
	begin
		zn := lnk.Zone;;
		w := lnk.Weight;

		if ArrHighlights[zn].bSolid then
			Exit;

		RSum := RSum + w * ArrHighlights[zn].Color.R;
		GSum := GSum + w * ArrHighlights[zn].Color.G;
		BSum := BSum + w * ArrHighlights[zn].Color.B;
		WSum := WSum + w;
	end;


var
	i, j: Integer;
	col : TGLColor;
	lnk : PVertexLink;
	vi  : PVertexInfo;
begin
	Assert(FbSmoothed);

	for i := 0 to VertexCount - 1 do begin
		RSum := 0;
		GSum := 0;
		BSum := 0;
		WSum := 0;

		vi := @FFillInfo.Verts[i];

		if bDebug then
			CalcAddLink(FFillInfo.Verts[i].SelfLink)
		else begin
			RSum := 255;
			GSum := 255;
			BSum := 255;
			WSum := 1;
		end;


		if Assigned(vi.FillLinks) then
			for j := 0 to Length(vi.FillLinks) - 1 do begin
				lnk := @vi.FillLinks[j];
				CalcAddLink(lnk^);
			end;


		if WSum > 0 then begin
			Assert(ValidColor(RSum / WSum));
			Assert(ValidColor(GSum / WSum));
			Assert(ValidColor(BSum / WSum));
			col.R := Round(RSum / WSum);
			col.G := Round(GSum / WSum);
			col.B := Round(BSum / WSum);
		end
		else
			col := clMeshDefault;
		FRawColors[i] := col;

	end;

	ApplyColorMode;
end;


procedure TGLMesh.ApplyColorMode;

	function ColInv(const Color: TGLColor): TGLColor; inline;
	begin
		Result.A := 127;
		Result.R := 255 - Color.R;
		Result.G := 255 - Color.G;
		Result.B := 255 - Color.B;
		// Result := FixColorBackgroundMatch(Result);
	end;


var
	i          : Integer;
	col, colRaw: TGLColor;
begin
	for i := 0 to VertexCount - 1 do begin
		colRaw := FRawColors[i];
		case FColorMode of
			cmNORMAL: col := colRaw;
			cmINVERTED: col := ColInv(colRaw);
			cmSILHOUETTE: col := ColInv(clSilhouette);
		end;
		FColors[i] := col;
	end;
end;


procedure TGLMesh.SetColorMode(AMode: TMeshColorMode);
begin
	if FColorMode <> AMode then begin
		FColorMode := AMode;
		ApplyColorMode;
	end;
end;


procedure TGLMesh.Redraw(bMaskOnly: Boolean = False);
	procedure DrawOutline;
	var
		i                : Integer;
		sm, ofx, ofy, ofz: Single;
	begin

		if Assigned(FFillInfo.CrossEdgesIndex) then begin
			sm := 0.20 * glGetScreenTo3DScale(Bounds.SphCenter);

			glLineWidth(0.5);
			// glColor4b(50, 50, 50, 100);
			glDisable(GL_LIGHTING);
			FGLSettings.BlendSwitch(True);
			FGLSettings.BlendFuncSwitch(GL_SRC_COLOR, GL_ZERO);

			// glDisableClientState(GL_COLOR_ARRAY);
			glDisableClientState(GL_NORMAL_ARRAY);
			glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, FGLCrossEdgesBuffer);

			for i := 0 to 3 * 3 * 3 - 1 do begin
				ofx := i div 9 mod 3 - 1;
				ofy := i div 3 mod 3 - 1;
				ofz := i div 1 mod 3 - 1;
				GlPushMatrix;
				glTranslatef(sm * ofx, sm * ofy, sm * ofz);
				glDrawElements(GL_LINES, Length(FFillInfo.CrossEdgesIndex) * 2,
					GL_UNSIGNED_INT, nil);
				GlPopMatrix;
			end;
			FGLSettings.BlendRevert;
			FGLSettings.BlendFuncRevert;
			glEnableClientState(GL_NORMAL_ARRAY);
			glEnable(GL_LIGHTING);
		end;
	end;


begin
	FGLValidator.CheckContext;
	Assert(SizeOf(TGLColor) = SizeOf(Glubyte) * 4);
	if (FGLColorsBuffer = 0) or (FGLVertexBuffer = 0) or { }
		(FGLNormalBuffer = 0) or (FGLFacesIndexBuffer = 0) then begin
		Assert(False);
		Exit;
	end;

	if not bMaskOnly then begin
		glBindBuffer(GL_ARRAY_BUFFER, FGLColorsBuffer);
		glBufferData(GL_ARRAY_BUFFER, SizeOf(TGLColor) * VertexCount,
			PGLColorArray(FColors), GL_STATIC_DRAW);
		glColorPointer(4, GL_UNSIGNED_BYTE, 0, nil);
		glEnableClientState(GL_COLOR_ARRAY);
	end else begin
		glColor4ubv(@FclMaskColor);
		glDisableClientState(GL_COLOR_ARRAY);
	end;

	glBindBuffer(GL_ARRAY_BUFFER, FGLVertexBuffer);
	glVertexPointer(3, GL_FLOAT, 0, nil);
	glEnableClientState(GL_VERTEX_ARRAY);

	if not bMaskOnly then begin
		glBindBuffer(GL_ARRAY_BUFFER, FGLNormalBuffer);
		glNormalPointer(GL_FLOAT, 0, nil);
		glEnableClientState(GL_NORMAL_ARRAY);
	end
	else
		glDisableClientState(GL_NORMAL_ARRAY);

	glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, FGLFacesIndexBuffer);
	glDrawElements(GL_TRIANGLES, FacesCount * 3, GL_UNSIGNED_INT, nil);
	// glPointSize(2);
	// glDrawElements(GL_POINTS, FacesCount * 3, GL_UNSIGNED_INT, nil);

	if FbOutlined and not bMaskOnly then
		DrawOutline;

	glDisableClientState(GL_VERTEX_ARRAY);
	glDisableClientState(GL_NORMAL_ARRAY);
	glDisableClientState(GL_COLOR_ARRAY);

end;

{ procedure TGLMesh.OldRedraw(SmoothNormals: Boolean);
  procedure DrawVert(const Id: Integer);
  begin
  glColor4ubv(@FColors[Id]);
  if SmoothNormals then
  glNormal3fv(@FSmoothNormals[Id]);
  glVertex3fv(@FVertices[Id]);
  end;

  var
  i, fs, Id: Integer;
  begin

  glBegin(GL_TRIANGLES);
  for i := 0 to FacesCount - 1 do begin
  DrawVert(FFaces[i].Id1);
  DrawVert(FFaces[i].Id2);
  DrawVert(FFaces[i].Id3);
  end;
  glEnd;

  end; }


function TGLMesh.DebugGetScreenVertexInfo(ScrX, ScrY: Integer): TVertexDebugInfo;
var
	i                  : Integer;
	vx, vy, vz         : GLDouble;
	sx, sy, sz         : GLDouble;
	modelMatrix        : TGLMatrixd4;
	projMatrix         : TGLMatrixd4;
	viewport           : TGLVectori4;
	minid              : Integer;
	mindst, len, delta2: Single;
	minX, minY         : Integer;
begin
	glGetDoublev(GL_MODELVIEW_MATRIX, @modelMatrix);
	glGetDoublev(GL_PROJECTION_MATRIX, @projMatrix);
	glGetIntegerv(GL_VIEWPORT, @viewport);

	mindst := SumInt(viewport);
	minid := -1;
	delta2 := 0;
	minX := 0;
	minY := 0;

	for i := 0 to VertexCount - 1 do begin
		vx := FVertices[i].x;
		vy := FVertices[i].y;
		vz := FVertices[i].z;

		gluProject(vx, vy, vz, modelMatrix, projMatrix, viewport, @sx, @sy, @sz);
		sy := viewport[3] - Round(sy);
		len := sqrt(Sqr(sx - ScrX) + Sqr(sy - ScrY) + Sqr(sz * 400));
		if mindst > len then begin
			delta2 := (mindst - len);
			mindst := len;
			minid := i;
			minX := Round(sx);
			minY := Round(sy);
		end;
	end;

	if minid >= 0 then begin
		Result.ScreenPos.x := minX;
		Result.ScreenPos.y := minY;
		Result.Pos := FVertices[minid];
		Result.HitLength := mindst;
		Result.HitLength2 := delta2;
		Result.Id := minid;
		Result.Links := FFillInfo.Verts[minid].FillLinks;
	end else begin
		Result.ScreenPos.x := 0;
		Result.ScreenPos.y := 0;
		Result.HitLength := MaxSingle;
		Result.Links := nil;
	end;

end;


constructor TGLMesh.Create;
begin
	inherited;

	VertexCount := 0;
	FbSmoothed := False;
	FbOutlined := False;

	FGLVertexBuffer := 0;
	FGLFacesIndexBuffer := 0;
	FGLCrossEdgesBuffer := 0;
	FGLNormalBuffer := 0;
	FGLColorsBuffer := 0;

	FclMaskColor := clMaskDefault;
end;


destructor TGLMesh.Destroy;
begin
	FFillInfo.Verts := nil;
	inherited;
end;


function TGLMesh.HasIntersects(const AMesh: TGLMesh; Gap: Single): Boolean;
var
	dist              : Single;
	bSepSph, bSepBox  : Boolean;
	bSepIdentical     : Boolean;
	AMX, AMN, BMX, BMN: TPoint3D;
begin
	dist := (Bounds.SphCenter - AMesh.Bounds.SphCenter).Length;
	bSepSph := (dist > (Bounds.SphRadius + AMesh.Bounds.SphRadius + Gap));

	AMX := AMesh.Bounds.BoxMax;
	AMN := AMesh.Bounds.BoxMin;
	BMX := Bounds.BoxMax;
	BMN := Bounds.BoxMin;

	bSepBox := False;
	bSepBox := bSepBox or (AMX.x + Gap < BMN.x) or (AMN.x > BMX.x + Gap);
	bSepBox := bSepBox or (AMX.y + Gap < BMN.y) or (AMN.y > BMX.y + Gap);
	bSepBox := bSepBox or (AMX.z + Gap < BMN.z) or (AMN.z > BMX.z + Gap);

	// Special similar dummy objects
	bSepIdentical := (FacesCount = AMesh.FacesCount) and (dist < Bounds.SphRadius / 10);

	Result := not(bSepSph or bSepBox or bSepIdentical);
end;


procedure TGLMesh.CalculateBoundingShape;
	procedure FindBoundingBox;
	var
		i             : Integer;
		vecMin, vecMax: TPoint3D;
	begin
		vecMin := FVertices[0];
		vecMax := FVertices[0];
		for i := 0 to VertexCount - 1 do begin
			vecMin.x := min(vecMin.x, FVertices[i].x);
			vecMin.y := min(vecMin.y, FVertices[i].y);
			vecMin.z := min(vecMin.z, FVertices[i].z);
			vecMax.x := max(vecMax.x, FVertices[i].x);
			vecMax.y := max(vecMax.y, FVertices[i].y);
			vecMax.z := max(vecMax.z, FVertices[i].z);

		end;

		Bounds.BoxMin := vecMin; // * 0.999;
		Bounds.BoxMax := vecMax; // * 1.001;
	end;

	procedure FindCenters;
	var
		vecCenterAvg, vecCenterBound: TPoint3D;
		i                           : Integer;
	begin
		vecCenterAvg := Point3D(0, 0, 0);
		for i := 0 to VertexCount - 1 do
			vecCenterAvg := vecCenterAvg + FVertices[i];
		vecCenterAvg := vecCenterAvg / VertexCount;
		vecCenterBound := (Bounds.BoxMin + Bounds.BoxMax) / 2;

		Bounds.SphCenter := (vecCenterAvg + vecCenterBound) / 2;
	end;

	procedure FindMaxRadius;
	var
		i        : Integer;
		vecRadius: TPoint3D;
		R        : Single;
	begin
		R := 0;

		for i := 0 to VertexCount - 1 do begin
			vecRadius := FVertices[i] - Bounds.SphCenter;
			R := max(R, vecRadius.Length);
		end;

		Bounds.SphRadius := R * 1.0001;
	end;


begin
	FindBoundingBox;
	FindCenters;
	FindMaxRadius;
end;


procedure TGLMesh.CreateVertexBuffers;
var
	EdgesCount: Integer;
begin
	Assert(SizeOf(TPoint3D) = SizeOf(GLfloat) * 3);
	Assert(SizeOf(TGLFace) = SizeOf(GLuint) * 3);

	try
		FGLValidator.RegisterContext;

		glGenBuffers(1, @FGLFacesIndexBuffer);
		glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, FGLFacesIndexBuffer);
		glBufferData(GL_ELEMENT_ARRAY_BUFFER, FacesCount * SizeOf(TGLFace), FFaces,
			GL_STATIC_DRAW);

		EdgesCount := Length(FFillInfo.CrossEdgesIndex);
		if (EdgesCount > 0) then begin
			glGenBuffers(1, @FGLCrossEdgesBuffer);
			glBindBuffer(GL_ELEMENT_ARRAY_BUFFER, FGLCrossEdgesBuffer);
			glBufferData(GL_ELEMENT_ARRAY_BUFFER, EdgesCount * SizeOf(TGLEdge),
				@FFillInfo.CrossEdgesIndex[0], GL_STATIC_DRAW);
		end;

		glGenBuffers(1, @FGLVertexBuffer);
		glBindBuffer(GL_ARRAY_BUFFER, FGLVertexBuffer);
		glBufferData(GL_ARRAY_BUFFER, VertexCount * SizeOf(TPoint3D), FVertices,
			GL_STATIC_DRAW);

		glGenBuffers(1, @FGLNormalBuffer);
		glBindBuffer(GL_ARRAY_BUFFER, FGLNormalBuffer);
		glBufferData(GL_ARRAY_BUFFER, VertexCount * SizeOf(TPoint3D), FSmoothNormals,
			GL_STATIC_DRAW);

		glGenBuffers(1, @FGLColorsBuffer);
		glBindBuffer(GL_ARRAY_BUFFER, FGLColorsBuffer);
		glBufferData(GL_ARRAY_BUFFER, VertexCount * SizeOf(TGLColor), FColors,
			GL_DYNAMIC_DRAW);

	except
		FreeVertexBuffers;
	end;

	Assert(FGLNormalBuffer <> 0);
end;


procedure TGLMesh.FreeVertexBuffers;
begin
	try
		FGLValidator.CheckContext;
		glDeleteBuffers(1, @FGLVertexBuffer);
		glDeleteBuffers(1, @FGLFacesIndexBuffer);
		glDeleteBuffers(1, @FGLCrossEdgesBuffer);
		glDeleteBuffers(1, @FGLNormalBuffer);
		glDeleteBuffers(1, @FGLColorsBuffer);
	finally
		FGLVertexBuffer := 0;
		FGLFacesIndexBuffer := 0;
		FGLCrossEdgesBuffer := 0;
		FGLNormalBuffer := 0;
		FGLColorsBuffer := 0;
	end;
end;


procedure TGLMesh.LoadFromStream(AStream: TStream);
var
	i          : Integer;
	Vertex     : TPoint3D;
	Normal     : TPoint3D;
	SNormal    : TPoint3D;
	Id, Version: Integer;
begin
	AStream.Read(Version, SizeOf(Version));
	if Version <> 2 then begin
		Assert(False);
		Exit;
	end;

	AStream.Read(bTransparent, SizeOf(bTransparent));
	AStream.Read(VertexCount, SizeOf(VertexCount));
	AStream.Read(FacesCount, SizeOf(FacesCount));

	SetLength(FVertices, VertexCount);
	SetLength(FSmoothNormals, VertexCount);
	SetLength(FFaces, FacesCount);
	SetLength(FFasetNormals, FacesCount);
	SetLength(FColors, VertexCount);
	SetLength(FRawColors, VertexCount);

	FFillInfo.Verts := nil;
	FFillInfo.CrossEdgesIndex := nil;

	for i := 0 to VertexCount - 1 do begin
		AStream.Read(Vertex.x, SizeOf(Vertex.x));
		AStream.Read(Vertex.y, SizeOf(Vertex.y));
		AStream.Read(Vertex.z, SizeOf(Vertex.z));

		FVertices[i] := Vertex;
	end;

	for i := 0 to FacesCount - 1 do begin
		AStream.Read(Id, SizeOf(Id));
		FFaces[i].Id1 := Id - 1;
		AStream.Read(Id, SizeOf(Id));
		FFaces[i].Id2 := Id - 1;
		AStream.Read(Id, SizeOf(Id));
		FFaces[i].Id3 := Id - 1;
	end;

	for i := 0 to FacesCount - 1 do begin
		AStream.Read(Normal.x, SizeOf(Normal.x));
		AStream.Read(Normal.y, SizeOf(Normal.y));
		AStream.Read(Normal.z, SizeOf(Normal.z));

		FFasetNormals[i] := Normal;
	end;

	for i := 0 to VertexCount - 1 do begin
		AStream.Read(SNormal.x, SizeOf(SNormal.x));
		AStream.Read(SNormal.y, SizeOf(SNormal.y));
		AStream.Read(SNormal.z, SizeOf(SNormal.z));

		FSmoothNormals[i] := SNormal;
	end;
end;


procedure TGLMesh.Assign(Source: TPersistent);
var
	SrcMesh: TGLMesh;
begin
	if Source is TGLMesh then begin
		Assert(Length(FFaces) = 0);

		SrcMesh := TGLMesh(Source);

		bTransparent := SrcMesh.bTransparent;
		VertexCount := SrcMesh.VertexCount;
		FacesCount := SrcMesh.FacesCount;
		fExtent := SrcMesh.fExtent;
		Bounds := SrcMesh.Bounds;

		FVertices := Copy(SrcMesh.FVertices);
		FSmoothNormals := Copy(SrcMesh.FSmoothNormals);
		FFaces := Copy(SrcMesh.FFaces);
		FFasetNormals := Copy(SrcMesh.FFasetNormals);
		FColors := Copy(SrcMesh.FColors);
		FRawColors := Copy(SrcMesh.FRawColors);

		FColorMode := SrcMesh.FColorMode;
		// const for all
		FFillInfo.Assign(SrcMesh.FFillInfo);

		FGLVertexBuffer := 0;
		FGLFacesIndexBuffer := 0;
		FGLCrossEdgesBuffer := 0;
		FGLNormalBuffer := 0;
		FGLColorsBuffer := 0;

		FclMaskColor := SrcMesh.FclMaskColor;
		FbSmoothed := SrcMesh.FbSmoothed;
		FbOutlined := SrcMesh.FbOutlined;

		FGLSettings.Reset;
		FGLValidator.Reset;
	end
	else
		inherited;

end;

{ TZoneFillInfo }


procedure TZoneFillInfo.Assign(Source: TZoneFillInfo);
begin
	Verts := Copy(Source.Verts);
	CrossEdgesIndex := Copy(Source.CrossEdgesIndex);
end;

end.
