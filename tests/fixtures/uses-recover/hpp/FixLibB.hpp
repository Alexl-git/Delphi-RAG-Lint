// CodeGear C++Builder
// Copyright (c) 1995, 2026 by Embarcadero Technologies, Inc.
// All rights reserved

// (DO NOT EDIT: machine generated header) 'FixLibB.pas' rev: 37.00 (Windows)

#ifndef FixLibBHPP
#define FixLibBHPP

#pragma delphiheader begin
#pragma option push
#if defined(__BORLANDC__) && !defined(__clang__)
#pragma option -w-      // All warnings off
#pragma option -Vx      // Zero-length empty class member 
#endif
#pragma pack(push,8)
#include <System.hpp>
#include <SysInit.hpp>
#include <FixRtl.hpp>

//-- user supplied -----------------------------------------------------------

namespace Fixlibb
{
//-- forward type declarations -----------------------------------------------
class DELPHICLASS TLibB;
//-- type declarations -------------------------------------------------------
#pragma pack(push,4)
class PASCALIMPLEMENTATION TLibB : public System::TObject
{
	typedef System::TObject inherited;
	
public:
	int __fastcall Value();
public:
	/* TObject.Create */ inline __fastcall TLibB() : System::TObject() { }
	/* TObject.Destroy */ inline __fastcall virtual ~TLibB() { }
	
};

#pragma pack(pop)

//-- var, const, procedure ---------------------------------------------------
}	/* namespace Fixlibb */
#if !defined(DELPHIHEADER_NO_IMPLICIT_NAMESPACE_USE) && !defined(NO_USING_NAMESPACE_FIXLIBB)
using namespace Fixlibb;
#endif
#pragma pack(pop)
#pragma option pop

#pragma delphiheader end.
//-- end unit ----------------------------------------------------------------
#endif	// FixLibBHPP
