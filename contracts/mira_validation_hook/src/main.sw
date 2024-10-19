contract;

use utils::utils::is_stable;
use interfaces::{data_structures::PoolId, mira_amm::MiraAMM};
use math::pool_math::{calculate_fee, validate_curve};

configurable {
    AMM_CONTRACT_ID: ContractId = ContractId::zero(),
}

abi IBaseHook {
    #[storage(read, write)]
    fn hook(
        pool_id: PoolId,
        sender: Identity,
        to: Identity,
        asset_0_in: u64,
        asset_1_in: u64,
        asset_0_out: u64,
        asset_1_out: u64,
        lp_token: u64,
    );
}

fn get_fee(input: u64, is_stable: bool, fees: (u64, u64, u64, u64)) -> u64 {
    let (lp_fee_volatile, lp_fee_stable, protocol_fee_volatile, protocol_fee_stable) = fees;
    let total_fee = if is_stable {
        lp_fee_stable + protocol_fee_stable
    } else {
        lp_fee_volatile + protocol_fee_volatile
    };
    calculate_fee(input, total_fee)
}

fn post_validate_curve(
    is_stable: bool,
    current_reserve_0: u64,
    current_reserve_1: u64,
    decimals_0: u8,
    decimals_1: u8,
    asset_0_in: u64,
    asset_1_in: u64,
    asset_0_out: u64,
    asset_1_out: u64,
    fees: (u64, u64, u64, u64),
) {
    let previous_reserve_0 = current_reserve_0 - asset_0_in + asset_0_out;
    let previous_reserve_1 = current_reserve_1 - asset_1_in + asset_1_out;
    let current_reserve_without_fee_0 = current_reserve_0 - get_fee(asset_0_in, is_stable, fees);
    let current_reserve_without_fee_1 = current_reserve_1 - get_fee(asset_1_in, is_stable, fees);

    validate_curve(
        is_stable,
        current_reserve_without_fee_0,
        current_reserve_without_fee_1,
        previous_reserve_0,
        previous_reserve_1,
        decimals_0,
        decimals_1,
    );
}

impl IBaseHook for Contract {
    #[storage(read, write)]
    fn hook(
        pool_id: PoolId,
        sender: Identity,
        to: Identity,
        asset_0_in: u64,
        asset_1_in: u64,
        asset_0_out: u64,
        asset_1_out: u64,
        lp_token: u64,
    ) {
        if (lp_token == 0) {
            // it's a swap
            let amm = abi(MiraAMM, AMM_CONTRACT_ID.into());
            let pool = amm.pool_metadata(pool_id).unwrap();
            let fees = amm.fees();
            post_validate_curve(
                is_stable(pool_id),
                pool.reserve_0,
                pool.reserve_1,
                pool.decimals_0,
                pool.decimals_1,
                asset_0_in,
                asset_1_in,
                asset_0_out,
                asset_1_out,
                fees,
            );
        }
    }
}

#[test]
fn test_fees() {
    assert_eq(get_fee(10, false, (30, 5, 0, 0)), 1);
    assert_eq(get_fee(0, false, (30, 5, 0, 0)), 0);
}

#[test]
fn test_post_validate_curve_volatile() {
    // is_stable, res_0, res_1, input_0, input_1, output_0, output_1, dec_0, dec_1
    let mut test_cases: Vec<(bool, u64, u64, u64, u64, u64, u64, u8, u8)> = Vec::new();

    // volatile pool, same decimals
    // 990 * 1001 (990_990) < (1000 - 1) * 1000 (999_000)
    test_cases.push((false, 1000, 1000, 10, 0, 1, 0, 6, 6));
    // 990 * 1009 (998_910) < (1000 - 1) * 1000 (999_000)
    test_cases.push((false, 1000, 1000, 10, 0, 0, 9, 6, 6));
    // 998_996 * 1002 (1_000_993_992) < (999_999 - 3) * 1001 (1_000_995_996)
    test_cases.push((false, 999_999, 1001, 1003, 0, 0, 1, 2, 2));
    // 998_996_989 * 1_002_000 (1_000_994_982_978_000) < (999_999_999 - 3009) * 1_001_000 (1_000_996_986_990_000)
    test_cases.push((false, 999_999_999, 1_001_000, 1_003_010, 0, 0, 1000, 2, 2));

    // volatile pool, different decimals
    // 990 * 1001 (990_990) < (1000 - 1) * 1000 (999_000)
    test_cases.push((false, 1000, 1000, 10, 0, 1, 0, 2, 8));
    // 990 * 1009 (998_910) < (1000 - 1) * 1000 (999_000)
    test_cases.push((false, 1000, 1000, 10, 0, 0, 9, 10, 0));
    // 998_996 * 1002 (1_000_993_992) < (999_999 - 3) * 1001 (1_000_995_996)
    test_cases.push((false, 999_999, 1001, 1003, 0, 0, 1, 2, 3));
    // 998_996_989 * 1_002_000 (1_000_994_982_978_000) < (999_999_999 - 3009) * 1_001_000 (1_000_996_986_990_000)
    test_cases.push((false, 999_999_999, 1_001_000, 1_003_010, 0, 0, 1000, 5, 4));

    let mut i = 0;
    while i < test_cases.len() {
        let (is_stable, res_0, res_1, input_0, input_1, output_0, output_1, dec_0, dec_1) = test_cases.get(i).unwrap();
        post_validate_curve(
            is_stable,
            res_0,
            res_1,
            dec_0,
            dec_1,
            input_0,
            input_1,
            output_0,
            output_1,
            (30, 5, 0, 0),
        );
        i = i + 1;
    }
}

#[test(should_revert)]
fn test_post_validate_curve_volatile_failure() {
    // is_stable, res_0, res_1, input_0, input_1, output_0, output_1, dec_0, dec_1
    let mut test_cases: Vec<(bool, u64, u64, u64, u64, u64, u64, u8, u8)> = Vec::new();

    // 990 * 1009 (998_910) < (1000 - 1) * 1000 (999_000) OK
    test_cases.push((false, 1000, 1000, 10, 0, 0, 9, 6, 6));
    // 990 * 1010 (999_900) < (1000 - 1) * 1000 (999_000) VIOLATION
    test_cases.push((false, 1000, 1000, 10, 0, 0, 10, 6, 6));

    let mut i = 0;
    while i < test_cases.len() {
        let (is_stable, res_0, res_1, input_0, input_1, output_0, output_1, dec_0, dec_1) = test_cases.get(i).unwrap();
        post_validate_curve(
            is_stable,
            res_0,
            res_1,
            dec_0,
            dec_1,
            input_0,
            input_1,
            output_0,
            output_1,
            (30, 5, 0, 0),
        );
        i = i + 1;
    }
}
