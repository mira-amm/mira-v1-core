library;

use std::string::String;
use ::data_structures::{
    Asset,
    PoolId,
    PoolInfo,
    RemoveLiquidityInfo,
    PoolInfoView,
};

// TODO: docs
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

    // TODO: be consistent and return more info, like in `remove_liquidity`
    #[storage(read, write)]
    fn add_liquidity(
        pool_id: PoolId,
        desired_liquidity: u64,
        deadline: u32,
    ) -> Asset;

    // TODO: return some info about the pool
    #[payable, storage(read, write)]
    fn deposit(pool_id: PoolId);

    #[payable, storage(read, write)]
    fn remove_liquidity(
        pool_id: PoolId,
        min_asset_a: u64,
        min_asset_b: u64,
        deadline: u32,
    ) -> RemoveLiquidityInfo;

    // TODO: return some info about the pool
    #[storage(read, write)]
    fn withdraw(pool_id: PoolId, asset: Asset);

    // TODO: move exact_input and exact_output to the router
    // TODO: return some info about the pool
    #[payable, storage(read, write)]
    fn swap_exact_input(
        pool_id: PoolId,
        min_output: u64,
        deadline: u32,
    ) -> u64;

    // TODO: return some info about the pool
    #[payable, storage(read, write)]
    fn swap_exact_output(pool_id: PoolId, output: u64, deadline: u32) -> u64;

    #[storage(read)]
    fn balance(pool_id: PoolId, asset_id: AssetId) -> u64;
}
