library;

use interfaces::data_structures::{Asset, PoolId};
use interfaces::errors::InputError;
use std::{hash::*, string::String, bytes::Bytes};

/// Validates that the provided pool id is correct, i.e.:
///  - has two distinct assets
///  - assets are ordered
pub fn validate_pool_id(pool_id: PoolId) {
    require(pool_id.0 != pool_id.1, InputError::IdenticalAssets);
    let pool_id_0_b256: b256 = pool_id.0.into();
    let pool_id_1_b256: b256 = pool_id.1.into();
    require(pool_id_0_b256 < pool_id_1_b256, InputError::UnsortedAssetPair);
}

/// Builds and returns an LP sub id and asset id for the provided pool id
pub fn get_lp_asset(pool_id: PoolId) -> (b256, AssetId) {
    validate_pool_id(pool_id);
    let lp_sub_id = sha256(pool_id);
    (lp_sub_id, AssetId::new(ContractId::this(), lp_sub_id))
}

pub fn build_lp_name(symbol_0: String, symbol_1: String) -> String {
    let mut result = Bytes::new();
    push_bytes(result, symbol_0.as_bytes());
    push_bytes(result, String::from_ascii_str("-").as_bytes());
    push_bytes(result, symbol_1.as_bytes());
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
