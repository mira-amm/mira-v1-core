library;

use std::{bytes::Bytes, string::String};
use ::data_structures::{Asset, PoolId, PoolInfo, PoolMetadata,};

abi MiraAMM {
    #[storage(read, write)]
    fn create_pool(
        token_0_contract_id: ContractId,
        token_0_sub_id: b256,
        token_1_contract_id: ContractId,
        token_1_sub_id: b256,
        is_stable: bool,
    ) -> PoolId;

    #[storage(read)]
    fn pool_metadata(pool_id: PoolId) -> PoolMetadata;

    #[storage(read)]
    fn pools() -> Vec<PoolId>;

    fn fees() -> (u64, u64, u64, u64);

    #[storage(read, write)]
    fn mint(pool_id: PoolId, to: Identity) -> Asset;

    #[payable]
    #[storage(read, write)]
    fn burn(pool_id: PoolId, to: Identity) -> (u64, u64);

    #[payable]
    #[storage(read, write)]
    fn swap(
        pool_id: PoolId,
        amount_0_out: u64,
        amount_1_out: u64,
        to: Identity,
        data: Bytes,
    );
}
