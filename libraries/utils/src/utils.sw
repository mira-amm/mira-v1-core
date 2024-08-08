library;

use interfaces::data_structures::{
    Asset,
    AssetPair,
    PoolId,
    PoolInfo,
};
use interfaces::errors::{PoolManagementError, InputError};
use std::{
    asset::{transfer},
    block::height,
    hash::*,
    string::String,
    bytes::Bytes
};

/// Deterministically orders the provided pair of assets
pub fn order_asset_pairs(asset_pair: (AssetId, AssetId)) -> (AssetId, AssetId) {
    let asset_pair_0_b256: b256 = asset_pair.0.into();
    let asset_pair_1_b256: b256 = asset_pair.1.into();

    if asset_pair_0_b256 < asset_pair_1_b256 {
        asset_pair
    } else {
        (asset_pair.1, asset_pair.0)
    }
}

/// Validates that the provided pool id is correct, i.e.:
///  - has two distinct assets
///  - assets are ordered
pub fn validate_pool_id(pool_id: PoolId) {
    require(pool_id.0 != pool_id.1, PoolManagementError::IdenticalAssets);
    let pool_id_0_b256: b256 = pool_id.0.into();
    let pool_id_1_b256: b256 = pool_id.1.into();
    require(
        pool_id_0_b256 < pool_id_1_b256,
        PoolManagementError::UnsortedAssetPair,
    );
}

/// Builds and returns an LP sub id and asset id for the provided pool id
pub fn get_lp_asset(pool_id: PoolId) -> (b256, AssetId) {
    validate_pool_id(pool_id);
    let lp_sub_id = sha256(pool_id);
    (lp_sub_id, AssetId::new(ContractId::this(), lp_sub_id))
}

/// Validates that the provided deadline hasn't passed yet
pub fn check_deadline(deadline: u32) {
    require(deadline > height(), InputError::DeadlinePassed(deadline));
}

pub fn send_asset_pair(to: Identity, pair: AssetPair) {
    if pair.a.amount > 0 {
        transfer(to, pair.a.id, pair.a.amount);
    }
    if pair.b.amount > 0 {
        transfer(to, pair.b.id, pair.b.amount);
    }
}

/// Determines the individual assets in an asset pair.
///
/// # Arguments
///
/// * `input_asset_id`: [AssetId] - The AssetId of the input asset.
/// * `pair`: [AssetPair] - The asset pair from which the individual assets are determined.
///
/// # Reverts
///
/// * When `input_asset_id` does not match the asset id of either asset in `pair`.
pub fn determine_assets(input_asset_id: AssetId, pair: AssetPair) -> (Asset, Asset) {
    require(
        input_asset_id == pair.a.id || input_asset_id == pair.b.id,
        InputError::InvalidAsset(input_asset_id),
    );
    (pair.this_asset(input_asset_id), pair.other_asset(input_asset_id))
}

pub fn build_lp_name(name_a: String, name_b: String) -> String {
    let mut result = Bytes::new();
    push_bytes(result, name_a.as_bytes());
    push_bytes(result, String::from_ascii_str("-").as_bytes());
    push_bytes(result, name_b.as_bytes());
    push_bytes(result, String::from_ascii_str(" LP").as_bytes());
    String::from_ascii(result)
}

fn push_bytes(ref mut a: Bytes, b: Bytes) {
    let mut i = 0;
    while i < b.len() {
        a.push(b.get(i).unwrap());
        i = i + 1;
    }
}
