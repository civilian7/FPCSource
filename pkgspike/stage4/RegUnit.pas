unit RegUnit;

{$mode delphi}

interface

uses
  Classes;

type
  TRegDemo = class(TComponent)
  end;

procedure Register;

implementation

procedure Register;
begin
  RegisterClass(TRegDemo);
end;

end.
