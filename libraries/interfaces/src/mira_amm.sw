library;

use std::string::String;
use ::data_structures::{
    Asset,
    PoolId,
    PoolInfo,
    RemoveLiquidityInfo,
    PoolInfoView,
    AssetPair,
};


// TODO: add pause?
// TODO: docs
// TODO: add fee management
abi MiraAMM {
    #[storage(read, write)]
    fn add_pool(
        token_a_contract_id: ContractId,
        token_a_sub_id: b256,
        token_b_contract_id: ContractId,
        token_b_sub_id: b256,
        is_stable: bool,
    );

    #[storage(read)]
    fn pool_info(pool_id: PoolId) -> PoolInfoView;

    #[storage(read)]
    fn pools() -> Vec<PoolId>;

    #[storage(read, write)]
    fn mint(pool_id: PoolId, to: Identity) -> Asset;

    #[payable]
    #[storage(read, write)]
    fn burn(pool_id: PoolId, to: Identity) -> AssetPair;

    #[payable]
    #[storage(read, write)]
    fn swap(pool_id: PoolId, amount_0_out: u64, amount_1_out: u64, to: Identity);
}
