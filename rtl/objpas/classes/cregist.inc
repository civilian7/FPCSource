{%MainUnit classes.pp}
{
    This file is part of the Free Component Library (FCL)
    Copyright (c) 1999-2000 by the Free Pascal development team

    See the file COPYING.FPC, included in this distribution,
    for details about the copyright.

    This program is distributed in the hope that it will be useful,
    but WITHOUT ANY WARRANTY; without even the implied warranty of
    MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.

 **********************************************************************}



{ Class registration routines }

procedure RegisterClass(AClass: TPersistentClass);
begin
  //Classlist is created during initialization.
  with Classlist.Locklist do
    try
      while Indexof(AClass) = -1 do
        begin
          if GetClass(AClass.Unitname,AClass.ClassName) <> nil then  //class alread registered!
            Begin
            //raise an error
            exit;
            end;
          Add(AClass);
          if AClass = TPersistent then break;
          AClass := TPersistentClass(AClass.ClassParent);
        end;
    finally
      ClassList.UnlockList;
    end;
end;


procedure RegisterClassAlias(AClass: TPersistentClass; const Alias: string);
  var
    I : integer;
    S : string;
  begin
    I:=-1;
    { Alias usually is a constant living in the caller's data section, so
      storing it below would only copy a pointer with refcount -1. If the
      caller is a package, that data section goes away on UnloadPackage, and
      both TStringList.Delete and the finalization of ClassAliasList would
      then finalize a string body at an unmapped address. An alias is only
      dropped when its class is unregistered, so one registered for a class
      owned by another module outlives its registrar for certain. Force a
      private copy on the host heap instead, so the stored alias outlives any
      package. }
    S:=Alias;
    UniqueString(S);
    ClassList.LockList;
    try
      if ClassAliasList=nil then
        ClassAliasList := TStringList.Create
      else
        i := ClassAliasList.IndexOf(S);
      if I = -1 then
        ClassAliasList.AddObject( S, TObject(AClass) );
    finally
      ClassList.UnlockList;
    end;
  end;


procedure RegisterClasses(AClasses: array of TPersistentClass);
var
  I : Integer;
begin
  for I := low(aClasses) to high(aClasses) do
    RegisterClass(aClasses[I]);
end;


procedure UnRegisterClass(AClass: TPersistentClass);

var
  i: Integer;
begin
  with ClassList.LockList do
    try
      Remove(AClass);
      if Assigned(ClassAliasList) then
        for i:=ClassAliasList.Count-1 downto 0 do
          if TPersistentClass(ClassAliasList.Objects[i])=AClass then
            ClassAliasList.Delete(i);
    finally
      ClassList.UnlockList;
    end;
end;


procedure UnRegisterClasses(const AClasses: array of TPersistentClass);

var
  i: Integer;
begin
  for i:=Low(AClasses) to high(AClasses) do
    UnRegisterClass(AClasses[i]);
end;


{$if defined(WIN32) or defined(WIN64)}
function StaleRegistryEntry(P: Pointer; Module: HMODULE): Boolean;
var
  info : TMemoryBasicInformation;
begin
  if VirtualQuery(P,info,SizeOf(info))<>SizeOf(info) then
    begin
      { the address is not part of this process' address space at all, so
        whatever put it in the registry is long gone }
      Result:=True;
      exit;
    end;
  { Either the entry belongs to the departing image, or it points at memory
    that is no longer committed. The second case catches an image that was
    unmapped as a *dependency*: UnloadPackage notifies the subscribers with
    the handle of the package it was asked to unload and only then calls
    FreeLibrary, which drops the reference counts of everything that package
    requires. An image released that way is unmapped without a module unload
    notification of its own, so its entries never matched any Module and
    stayed behind. Memory that is no longer committed cannot belong to any
    live class, so such entries are safe to drop.

    Note this only reclaims entries whose image is still unmapped when some
    later unload runs the sweep. It does not bound growth across an
    install/uninstall/reinstall cycle of the same package: the sweep runs
    from the unload notification, i.e. before FreeLibrary, and a package
    reloaded in between is normally mapped at its previous base again (these
    images have a fixed image base, so the addresses coincide exactly), which
    makes the leftovers indistinguishable from the live registrations. Fixing
    that needs the registering module recorded per entry, which this list has
    never carried. }
  Result:=(HMODULE(info.AllocationBase)=Module) or (info.State<>MEM_COMMIT);
end;
{$endif}

procedure UnRegisterModuleClasses(Module: HMODULE);
{$if defined(WIN32) or defined(WIN64)}
var
  i : Integer;
begin
  { drop every class whose VMT lives inside the departing image.
    RegisterClass registers the whole ancestor chain, so a package's
    finalization (which typically unregisters only its own classes)
    leaves ancestors behind; any of those belonging to the unloaded
    module would dangle in the list. The chain also crosses images -- a
    design-time package registering a class derived from one in the runtime
    package it requires puts that ancestor here -- so entries orphaned by an
    earlier dependency unmap go too. }
  with ClassList.LockList do
    try
      for i:=Count-1 downto 0 do
        if StaleRegistryEntry(Items[i],Module) then
          UnRegisterClass(TPersistentClass(Items[i]));
    finally
      ClassList.UnlockList;
    end;
end;
{$else}
begin
end;
{$endif}

function FindClass(const AClassName: string): TPersistentClass;

begin
  Result := FindClass('',AClassName);
end;

function FindClass(const anUnitname, aClassName: string): TPersistentClass;
begin
  Result := GetClass(anUnitname,aClassName);
  if not Assigned(Result) then
    if anUnitname<>'' then
      raise EClassNotFound.CreateFmt(SClassNotFound, [anUnitname+'/'+AClassName])
    else
      raise EClassNotFound.CreateFmt(SClassNotFound, [AClassName]);
end;

function GetClass(const AClassName: string): TPersistentClass;
begin
  Result:=GetClass('',AClassName);
end;

function GetClass(const anUnitname, aClassName: string): TPersistentClass;
var
  I : Integer;
begin
  with ClassList.LockList do
   try
     for I := 0 to Count-1 do
       begin
         Result := TPersistentClass(Items[I]);
         if not Result.ClassNameIs(AClassName) then
           continue;
         if (anUnitname='') or SameText(anUnitname,Result.UnitName) then
           exit;
       end;
     if Assigned(ClassAliasList) then
       begin
       I:=-1;
       if anUnitname<>'' then
         I := ClassAliasList.Indexof(anUnitname+'/'+AClassName);
       if I<0 then
         I := ClassAliasList.Indexof(AClassName);
       if I >= 0 then  //found
         Begin
         Result := TPersistentClass(ClassAliasList.Objects[i]);
         exit;
         end;
       end;
     Result := nil;
   finally
     ClassList.Unlocklist;
   end;
end;

procedure StartClassGroup(AClass: TPersistentClass);
begin
end;


procedure GroupDescendentsWith(AClass, AClassGroup: TPersistentClass);
begin
end;


function ActivateClassGroup(AClass: TPersistentClass): TPersistentClass;
begin
  Result:=nil;
end;


function ClassGroupOf(AClass: TPersistentClass): TPersistentClass;
begin
  Result:=nil;
end;


function ClassGroupOf(Instance: TPersistent): TPersistentClass;
begin
  Result:=nil;
end;


{ Component registration routines }

type
  TComponentPage = class(TCollectionItem)
  public
    Name: String;
    Classes: TList;
    destructor Destroy; override;
  end;

{ TComponentPage }

destructor TComponentPage.Destroy;
begin
  Classes.Free;
  inherited Destroy;
end;

var
  ComponentPages: TCollection;

procedure InitComponentPages;
begin
  ComponentPages := TCollection.Create(TComponentPage);
  { Add a empty page which will be used for storing the NoIcon components }
  ComponentPages.Add;
end;

procedure RegisterComponents(const Page: string;
  ComponentClasses: array of TComponentClass);
var
  i: Integer;
  pg: TComponentPage;
begin
  if Page = '' then exit;  { prevent caller from doing nonsense }

  pg := nil;
  if not Assigned(ComponentPages) then
    InitComponentPages
  else
    for i := 0 to ComponentPages.Count - 1 do
      if TComponentPage(ComponentPages.Items[i]).Name = Page then begin
        pg := TComponentPage(ComponentPages.Items[i]);
        break;
      end;

  if pg = nil then begin
    pg := TComponentPage(ComponentPages.Add);
    pg.Name := Page;
    { Page usually is a constant living in the caller's data section, so the
      assignment above only copies a pointer with refcount -1. If the caller
      is a package, that data section goes away on UnloadPackage, and both
      UnRegisterModuleComponents and the finalization of ComponentPages would
      then finalize a string body at an unmapped address. Force a private copy
      on the host heap instead, so the stored name outlives any package. }
    UniqueString(pg.Name);
  end;

  if pg.Classes = nil then
    pg.Classes := TList.Create;

  for i := Low(ComponentClasses) to High(ComponentClasses) do
    pg.Classes.Add(ComponentClasses[i]);

  if Assigned(RegisterComponentsProc) then
    RegisterComponentsProc(Page, ComponentClasses);
end;


procedure RegisterNoIcon(ComponentClasses: array of TComponentClass);
var
  pg: TComponentPage;
  i: Integer;
begin
  if not Assigned(ComponentPages) then
    InitComponentPages;

  pg := TComponentPage(ComponentPages.Items[0]);
  if pg.Classes = nil then
    pg.Classes := TList.Create;

  for i := Low(ComponentClasses) to High(ComponentClasses) do
    pg.Classes.Add(ComponentClasses[i]);

  if Assigned(RegisterNoIconProc) then
    RegisterNoIconProc(ComponentClasses);
end;


procedure RegisterNonActiveX(ComponentClasses: array of TComponentClass;
  AxRegType: TActiveXRegType);

begin
end;


procedure UnRegisterModuleComponents(Module: HMODULE);
{$if defined(WIN32) or defined(WIN64)}
var
  i,j : Integer;
  pg : TComponentPage;
begin
  { counterpart of UnRegisterModuleClasses for the component palette.
    RegisterComponents/RegisterNoIcon record the component classes here
    before handing them to the IDE hook, so a package that unregisters
    itself through that hook still leaves its VMT pointers in this list;
    they would dangle once the image is unmapped. Registration and
    implementation routinely live in different images -- the unit calling
    RegisterComponents sits in the design-time package while the component
    classes come from the runtime package it requires -- so this list is the
    likeliest place to find entries orphaned by an earlier dependency unmap,
    and StaleRegistryEntry sweeps those out as well. }
  if not Assigned(ComponentPages) then
    exit;
  for i:=ComponentPages.Count-1 downto 0 do
    begin
      pg:=TComponentPage(ComponentPages.Items[i]);
      if Assigned(pg.Classes) then
        for j:=pg.Classes.Count-1 downto 0 do
          if StaleRegistryEntry(pg.Classes[j],Module) then
            pg.Classes.Delete(j);
      { A page that lost all its components is dropped, except for index 0:
        that one is the page reserved for the NoIcon components and
        RegisterNoIcon addresses it by position. }
      if (i>0) and ((pg.Classes=nil) or (pg.Classes.Count=0)) then
        pg.Free;
    end;
end;
{$else}
begin
end;
{$endif}

{$if defined(WIN32) or defined(WIN64)}
procedure ModuleUnloadHandler(Module: HMODULE);
begin
  UnRegisterModuleClasses(Module);
  UnRegisterModuleComponents(Module);
end;
{$endif}


