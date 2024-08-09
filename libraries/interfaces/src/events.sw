library;

use ::data_structures::{Asset, PoolId};

pub struct RegisterPoolEvent {
    pub pool_id: PoolId,
}

pub struct MintEvent {
    pub pool_id: PoolId,
    pub recipient: Identity,
    pub liquidity: Asset,
    pub asset_0_in: u64,
    pub asset_1_in: u64,
}

pub struct BurnEvent {
    pub pool_id: PoolId,
    pub recipient: Identity,
    pub liquidity: Asset,
    pub asset_0_out: u64,
    pub asset_1_out: u64,
}

pub struct SwapEvent {
    pub pool_id: PoolId,
    pub recipient: Identity,
    pub asset_0_in: u64,
    pub asset_1_in: u64,
    pub asset_0_out: u64,
    pub asset_1_out: u64,
}
