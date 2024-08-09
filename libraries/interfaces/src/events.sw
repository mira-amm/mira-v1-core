library;

use ::data_structures::{Asset, AssetPair, PoolId};

pub struct RegisterPoolEvent {
    pub pool_id: PoolId,
}

pub struct MintEvent {
    pub pool_id: PoolId,
    pub recipient: Identity,
    pub liquidity: Asset,
    pub assets_in: AssetPair,
}

pub struct BurnEvent {
    pub pool_id: PoolId,
    pub recipient: Identity,
    pub liquidity: Asset,
    pub assets_out: AssetPair,
}

pub struct SwapEvent {
    pub pool_id: PoolId,
    pub recipient: Identity,
    pub assets_in: AssetPair,
    pub assets_out: AssetPair,
}
