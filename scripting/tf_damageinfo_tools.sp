/**
 * [TF2] DamageInfo Tools
 */
#pragma semicolon 1
#include <sourcemod>

#pragma newdecls required

#include <sdktools>

#include <sourcescramble>
#include <stocksoup/handles>

// autogenerated class definitions; the build system handles this
#include <classdefs/take_damage_info.sp>
#include <classdefs/tf_radius_damage_info.sp>

#define PLUGIN_VERSION "0.1.0"
public Plugin myinfo = {
	name = "[TF2] DamageInfo Tools",
	author = "nosoop",
	description = "Library to generate damage events",
	version = PLUGIN_VERSION,
	url = "https://github.com/nosoop/SM-TFDamageInfo"
}

#define FLT_MAX view_as<float>(0x7f7fffff)

#define BASEDAMAGE_NOT_SPECIFIED FLT_MAX

Handle g_SDKCallRadiusDamageCalculateFalloff;
Handle g_SDKCallGameRulesRadiusDamage;

public APLRes AskPluginLoad2(Handle myself, bool late, char[] error, int err_max) {
	RegPluginLibrary("tf2_damageinfo_tools");
	
	CreateNative("TFDI_CTakeDamageInfo.TFDI_CTakeDamageInfo", Native_TakeDamageInfoCreate);
	CreateNative("TFDI_CTFRadiusDamageInfo.TFDI_CTFRadiusDamageInfo", Native_RadiusDamageInfoCreate);
	CreateNative("TFDI_CTFRadiusDamageInfo.Apply", Native_RadiusDamageInfoApply);
	
	return APLRes_Success;
}

public void OnPluginStart() {
	Handle hGameConf = LoadGameConfigFile("tf2.damageinfo_tools");
	if (!hGameConf) {
		SetFailState("Failed to load gamedata (tf2.damageinfo_tools).");
	}
	
	StartPrepSDKCall(SDKCall_Raw);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature,
			"CTFRadiusDamageInfo::CalculateFalloff()");
	g_SDKCallRadiusDamageCalculateFalloff = EndPrepSDKCall();
	
	StartPrepSDKCall(SDKCall_GameRules);
	PrepSDKCall_SetFromConf(hGameConf, SDKConf_Signature,
			"CTFGameRules::RadiusDamage(CTFRadiusDamageInfo&)");
	PrepSDKCall_AddParameter(SDKType_PlainOldData, SDKPass_Plain);
	g_SDKCallGameRulesRadiusDamage = EndPrepSDKCall();
	
	delete hGameConf;
}

/** 
 * CTakeDamageInfo(int inflictor, int attacker, float damage, int damagetype,
 *         int weapon, const float damageForce[3] = NULL_VECTOR,
 *         const float damagePosition[3] = NULL_VECTOR,
 *         const float reportedPosition[3] = NULL_VECTOR, int damagecustom = 0);
 */
public int Native_TakeDamageInfoCreate(Handle plugin, int nParams) {
	int inflictor = GetNativeCell(1);
	int attacker = GetNativeCell(2);
	float damage = GetNativeCell(3);
	int damagetype = GetNativeCell(4);
	int weapon = GetNativeCell(5);
	
	float damageForce[3];
	GetNativeArray(6, damageForce, sizeof(damageForce));
	
	float damagePosition[3];
	GetNativeArray(7, damagePosition, sizeof(damagePosition));
	
	float reportedPosition[3];
	GetNativeArray(8, reportedPosition, sizeof(reportedPosition));
	
	int damagecustom = GetNativeCell(9);
	
	MemoryBlock damageInfoData = new MemoryBlock(CTakeDamageInfo.GetClassSize());
	
	// create CTakeDamageInfo struct view from MemoryBlock
	CTakeDamageInfo damageInfo = CTakeDamageInfo.FromAddress(damageInfoData.Address);
	
	damageInfo.m_hInflictor = GetEntityHandle(inflictor);
	if (IsValidEntity(attacker)) {
		damageInfo.m_hAttacker = GetEntityHandle(attacker);
	} else {
		damageInfo.m_hAttacker = GetEntityHandle(inflictor);
	}

	damageInfo.m_hWeapon = GetEntityHandle(weapon);

	damageInfo.m_flDamage = damage;

	damageInfo.m_flBaseDamage = BASEDAMAGE_NOT_SPECIFIED;

	damageInfo.m_bitsDamageType = damagetype;
	damageInfo.m_iDamageCustom = damagecustom;

	damageInfo.m_flMaxDamage = damage;
	damageInfo.SetDamageForce(damageForce);
	damageInfo.SetDamagePosition(damagePosition);
	damageInfo.SetReportedPosition(reportedPosition);
	damageInfo.m_iAmmoType = -1;
	damageInfo.m_iDamagedOtherPlayers = 0;
	damageInfo.m_iPlayerPenetrationCount = 0;
	damageInfo.m_flDamageBonus = 0.0;
	damageInfo.m_bForceFriendlyFire = false;
	damageInfo.m_flDamageForForce = 0.0;
	
	damageInfo.m_eCritType = 0;
	
	// pass our MemoryBlock to the calling plugin. the receiving plugin shouldn't be concerned
	// about the underlying handle type.
	return MoveHandle(damageInfoData, plugin);
}

/** 
 * CTFRadiusDamageInfo(CTakeDamageInfo info, const float src[3], float radius,
 *         int ignoreEntity = INVALID_ENT_REFERENCE, float blastJumpRadius = 0.0,
 *         float forceScale = 1.0);
 */
public int Native_RadiusDamageInfoCreate(Handle plugin, int nParams) {
	MemoryBlock damageInfoData = GetNativeCell(1);
	
	float vecSrcIn[3];
	GetNativeArray(2, vecSrcIn, sizeof(vecSrcIn));
	
	float radius = GetNativeCell(3);
	int ignoreEntity = GetNativeCell(4);
	float blastJumpRadius = GetNativeCell(5);
	float forceScale = GetNativeCell(6);
	
	MemoryBlock radiusInfoData = new MemoryBlock(CTFRadiusDamageInfo.GetClassSize());
	
	// create a struct view into our memoryblock
	CTFRadiusDamageInfo radiusInfo = CTFRadiusDamageInfo.FromAddress(radiusInfoData.Address);
	
	radiusInfo.m_dmgInfo = CTakeDamageInfo.FromAddress(damageInfoData.Address);
	radiusInfo.SetVecSrc(vecSrcIn);
	radiusInfo.m_flRadius = radius;
	radiusInfo.m_pEntityIgnore = IsValidEntity(ignoreEntity)? GetEntityAddress(ignoreEntity) : Address_Null;
	radiusInfo.m_flRJRadius = blastJumpRadius;
	radiusInfo.m_flFalloff = 0.0;
	radiusInfo.m_flForceScale = forceScale;
	radiusInfo.m_pEntityTarget = Address_Null;
	
	// call CTFRadiusDamageInfo::CalculateFalloff(), just like the actual constructor
	SDKCall(g_SDKCallRadiusDamageCalculateFalloff, radiusInfo.Address);
	
	// pass our MemoryBlock to the calling plugin. the receiving plugin shouldn't be concerned
	// about the underlying handle type.
	return MoveHandle(radiusInfoData, plugin);
}

/**
 * CTFRadiusDamageInfo::Apply()
 */
public int Native_RadiusDamageInfoApply(Handle plugin, int nParams) {
	MemoryBlock radiusInfoData = GetNativeCell(1);
	SDKCall(g_SDKCallGameRulesRadiusDamage, radiusInfoData.Address);
}

static stock int GetEntityHandle(int entity) {
	return IsValidEntity(entity)? EntIndexToEntRef(entity) & ~(1 << 31) : 0;
}

static stock int GetEntityFromHandle(int entity) {
	return EntRefToEntIndex(entity | (1 << 31));
}
