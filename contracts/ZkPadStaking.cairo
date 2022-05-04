%lang starknet

from starkware.cairo.common.cairo_builtins import HashBuiltin, BitwiseBuiltin
from starkware.cairo.common.uint256 import (
    Uint256,
    uint256_add,
    uint256_le,
    uint256_lt,
    uint256_sub,
    uint256_check,
)
from starkware.cairo.common.math import (
    assert_not_equal,
    assert_not_zero,
    assert_le,
    assert_lt,
    unsigned_div_rem,
)
from starkware.cairo.common.pow import pow
from starkware.cairo.common.bitwise import bitwise_and, bitwise_xor, bitwise_or
from starkware.cairo.common.alloc import alloc
from starkware.cairo.common.bool import TRUE, FALSE
from starkware.cairo.common.registers import get_label_location
from starkware.starknet.common.syscalls import (
    get_caller_address,
    get_contract_address,
    get_block_timestamp,
)

from openzeppelin.access.ownable import Ownable_only_owner, Ownable_initializer, Ownable_get_owner
from openzeppelin.introspection.IERC165 import IERC165
from openzeppelin.token.erc20.interfaces.IERC20 import IERC20
from openzeppelin.token.erc721.interfaces.IERC721 import IERC721
from openzeppelin.security.safemath import (
    uint256_checked_add,
    uint256_checked_sub_lt,
    uint256_checked_sub_le,
    uint256_checked_mul,
    uint256_checked_div_rem,
)
from openzeppelin.security.pausable import (
    Pausable_when_not_paused,
    Pausable_when_paused,
    Pausable_pause,
    Pausable_unpause,
)
from openzeppelin.token.erc20.library import (
    ERC20_approve,
    ERC20_burn,
    ERC20_transfer,
    ERC20_transferFrom,
    ERC20_mint,
)
from contracts.openzeppelin.security.reentrancy_guard import (
    ReentrancyGuard_start,
    ReentrancyGuard_end,
)
from openzeppelin.upgrades.library import (
    Proxy_only_admin,
    Proxy_initializer,
    Proxy_get_implementation,
    Proxy_set_implementation,
)

from contracts.erc4626.ERC4626 import (
    name,
    symbol,
    totalSupply,
    decimals,
    balanceOf,
    allowance,
    asset,
    totalAssets,
    convertToShares,
    convertToAssets,
    maxDeposit,
    maxMint,
    maxWithdraw,
    previewWithdraw,
    maxRedeem,
    previewRedeem,
    ERC4626_withdraw,
    ERC4626_deposit,
    ERC4626_initializer,
    ERC4626_redeem,
    ERC4626_mint,
    ERC4626_previewDeposit,
    ERC4626_previewMint,
    ERC4626_convertToShares,
    decrease_allowance_by_amount,
    set_default_lock_time,
    days_to_seconds,
    calculate_lock_time_bonus,
    default_lock_time_days,
)
from contracts.utils import uint256_is_zero, get_array

# from contracts.ZkPadStrategyManager import constructor

const IERC721_ID = 0x80ac58cd

@contract_interface
namespace IMintCalculator:
    func getPoolAddress() -> (address : felt):
    end

    func getAmountToMint(input : Uint256) -> (amount : Uint256):
    end
end

struct WhitelistedToken:
    member bit_mask : felt
    member mint_calculator_address : felt
end

# # @notice Data for a given strategy.
# # @param trusted Whether the strategy is trusted.
# # @param balance The amount of underlying tokens held in the strategy.
struct StrategyData:
    member trusted : felt  # 0 (false) or 1 (true)
    member balance : felt
end

#
# Events
#
@event
func DepositLP(
    depositor : felt, receiver : felt, lp_address : felt, assets : Uint256, shares : Uint256
):
end

@event
func RedeemLP(receiver : felt, owner : felt, lp_token : felt, assets : Uint256, shares : Uint256):
end

@event
func WithdrawLP(
    caller : felt,
    receiver : felt,
    owner : felt,
    lp_token : felt,
    assets : Uint256,
    shares : Uint256,
):
end

@event
func FeePercentUpdated(user : felt, newFeePercent : felt):
end

@event
func HarvestWindowUpdated(user : felt, newHarvestWindow : felt):
end

# @notice Emitted when the harvest delay is updated.
# @param user The authorized user who triggered the update.
# @param newHarvestDelay The new harvest delay.
@event
func HarvestDelayUpdated(user : felt, newHarvestDelay : felt):
end

# @notice Emitted when the harvest delay is scheduled to be updated next harvest.
# @param user The authorized user who triggered the update.
# @param newHarvestDelay The scheduled updated harvest delay.
@event
func HarvestDelayUpdateScheduled(user : felt, newHarvestDelay : felt):
end

# @notice Emitted when the target float percentage is updated.
# @param user The authorized user who triggered the update.
# @param newTargetFloatPercent The new target float percentage.
@event
func TargetFloatPercentUpdated(user : felt, newTargetFloatPercent : Uint256):
end

#
# Storage variables
#

@storage_var
func whitelisted_tokens(lp_token : felt) -> (details : WhitelistedToken):
end

@storage_var
func token_mask_addresses(bit_mask : felt) -> (address : felt):
end

# bit mask with all whitelisted LP tokens
@storage_var
func whitelisted_tokens_mask() -> (mask : felt):
end

@storage_var
func deposits(user : felt, token_address : felt) -> (amount : Uint256):
end

@storage_var
func deposit_unlock_time(user : felt) -> (unlock_time : felt):
end

@storage_var
func user_staked_tokens(user : felt) -> (tokens_mask : felt):
end

# value is multiplied by 10 to store floating points number in felt type
@storage_var
func lp_stake_boost() -> (boost : felt):
end

@storage_var
func emergency_breaker() -> (address : felt):
end

@storage_var
func base_unit() -> (unit : felt):
end

@storage_var
func fee_percent() -> (fee : felt):
end

@storage_var
func harvest_window() -> (window : felt):
end

@storage_var
func harvest_delay() -> (delay : felt):
end

@storage_var
func next_harvest_delay() -> (delay : felt):
end

# # @notice The desired float percentage of holdings.
# # @dev A fixed point number where 1e18 represents 100% and 0 represents 0%.
@storage_var
func target_float_percent() -> (percent : Uint256):
end

# # @notice The total amount of underlying tokens held in strategies at the time of the last harvest.
# # @dev Includes maxLockedProfit, must be correctly subtracted to compute available/free holdings.
@storage_var
func total_strategy_holdings() -> (holdings : Uint256):
end

# # @notice Maps strategies to data the Vault holds on them.
@storage_var
func strategy_data(strategy : felt) -> (data : StrategyData):
end

# # @notice A timestamp representing when the first harvest in the most recent harvest window occurred.
# # @dev May be equal to lastHarvest if there was/has only been one harvest in the most last/current window.
@storage_var
func last_harvest_window_start() -> (start : felt):
end

# # @notice A timestamp representing when the most recent harvest occurred.
@storage_var
func last_harvest() -> (harvest : felt):
end

# # @notice The amount of locked profit at the end of the last harvest.
@storage_var
func max_locked_profit() -> (profit : felt):
end

# # @notice An ordered array of strategies representing the withdrawal queue.
# # @dev The queue is processed in descending order.
# # @dev Returns a tupled-array of (array_len, Strategy[])
@storage_var
func withdrawal_queue(index : felt) -> (strategy_address : felt):
end

@storage_var
func withdrawal_queue_length() -> (length : felt):
end

#
# View
#

@view
func isTokenWhitelisted{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    lp_token : felt
) -> (res : felt):
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    if whitelisted_token.bit_mask == 0:
        return (FALSE)
    end
    return (TRUE)
end

@view
func previewDeposit{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assets : Uint256
) -> (shares : Uint256):
    let (default_lock_period : felt) = default_lock_time_days.read()
    let (shares) = ERC4626_previewDeposit(assets, default_lock_period)
    return (shares)
end

@view
func previewDepositForTime{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    assets : Uint256, lock_time : felt
) -> (shares : Uint256):
    let (shares : Uint256) = ERC4626_convertToShares(assets)
    let (result : Uint256) = calculate_lock_time_bonus(shares, lock_time)
    return (result)
end

# Amount of xZKP a user will receive by providing LP token
# lp_token Address of the ZKP/ETH LP token
# assets Amount of LP tokens or the NFT id
# lock_time Number of days user lock the tokens
@view
func previewDepositLP{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    lp_token : felt, assets : Uint256, lock_time : felt
) -> (shares : Uint256):
    alloc_locals
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    with_attr error_message("invalid mint calculator address"):
        assert_not_zero(whitelisted_token.mint_calculator_address)
    end
    with_attr error_message("invalid token amount or nft id"):
        let (is_zero) = uint256_is_zero(assets)
        assert is_zero = FALSE
    end
    # convert to ZKP
    let (zkp_quote : Uint256) = IMintCalculator.getAmountToMint(
        whitelisted_token.mint_calculator_address, assets
    )
    let (shares : Uint256) = ERC4626_previewDeposit(zkp_quote, lock_time)
    let (current_lp_boost : felt) = lp_stake_boost.read()
    if current_lp_boost == 0:
        return (shares)
    end
    let (applied_boost : Uint256) = uint256_checked_mul(shares, Uint256(current_lp_boost, 0))
    let (res : Uint256, _) = uint256_checked_div_rem(applied_boost, Uint256(10, 0))
    return (res)
end

@view
func previewMint{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256
) -> (assets : Uint256):
    let (default_lock_period : felt) = default_lock_time_days.read()
    let (assets) = ERC4626_previewMint(shares, default_lock_period)
    return (assets)
end

@view
func previewMintForTime{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    shares : Uint256, lock_time : felt
) -> (assets : Uint256):
    let (assets) = ERC4626_previewMint(shares, lock_time)
    return (assets)
end

@view
func getCurrentBoostValue{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    res : felt
):
    let (res : felt) = lp_stake_boost.read()
    return (res)
end

@view
func getUserStakeInfo{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(user : felt) -> (unlock_time : felt, tokens_len : felt, tokens : felt*):
    alloc_locals
    let (unlock_time : felt) = deposit_unlock_time.read(user)
    let (user_bit_mask : felt) = user_staked_tokens.read(user)

    let (staked_tokens_array : felt*) = alloc()
    let (array_len : felt) = get_tokens_addresses_from_mask(
        0, user_bit_mask, 0, staked_tokens_array
    )
    return (unlock_time, array_len, staked_tokens_array)
end

@view
func getTokensMask{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    tokens_mask : felt
):
    let (bit_mask : felt) = whitelisted_tokens_mask.read()
    return (bit_mask)
end

@view
func getEmergencyBreaker{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    address : felt
):
    let (address : felt) = emergency_breaker.read()
    return (address)
end

@view
func getImplementation{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    address : felt
):
    let (address) = Proxy_get_implementation()
    return (address)
end

@view
func previewRedeemLP{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    lp_token : felt, shares : Uint256
) -> (amount : Uint256):
    alloc_locals
    only_whitelisted_token(lp_token)
    let (caller_address : felt) = get_caller_address()
    assert_not_before_unlock_time(caller_address)
    let (lp_withdraw_amount : Uint256) = calculate_withdraw_lp_amount(
        caller_address, lp_token, shares
    )
    return (lp_withdraw_amount)
end

@view
func previewWithdrawLP{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    lp_token : felt, input : Uint256
) -> (amount : Uint256):
    only_whitelisted_token(lp_token)
    let (caller_address : felt) = get_caller_address()
    assert_not_before_unlock_time(caller_address)
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    let (output : Uint256) = IMintCalculator.getAmountToMint(
        whitelisted_token.mint_calculator_address, input
    )
    return (output)
end

@view
func getDefaultLockTime{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    lock_time : felt
):
    let (lock_time : felt) = default_lock_time_days.read()
    return (lock_time)
end

# # @notice Gets the full withdrawal queue.
# # @return An ordered array of strategies representing the withdrawal queue.
@view
func getWithdrawalQueue{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    queue_len : felt, queue : felt*
):
    alloc_locals
    let (length : felt) = withdrawal_queue_length.read()
    let (mapping_ref : felt) = get_label_location(withdrawal_queue.read)
    let (array : felt*) = alloc()

    get_array(length, array, mapping_ref)
    return (length, array)
end

@view
func totalFloat{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}() -> (
    float : Uint256
):
    let (current_float_percent : Uint256) = target_float_percent.read()
    return (current_float_percent)
end

#
# Externals
#

@external
func initializer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    name : felt, symbol : felt, asset_addr : felt, owner : felt
):
    alloc_locals
    assert_not_zero(owner)
    Proxy_initializer(owner)
    ERC4626_initializer(name, symbol, asset_addr)
    Ownable_initializer(owner)

    let (decimals : felt) = IERC20.decimals(asset_addr)
    let (asset_base_unit : felt) = pow(10, decimals)
    base_unit.write(asset_base_unit)
    # # Add ZKP token to the whitelist and bit mask on first position
    token_mask_addresses.write(1, asset_addr)
    whitelisted_tokens_mask.write(1)
    whitelisted_tokens.write(asset_addr, WhitelistedToken(1, 0))
    return ()
end

@external
func upgrade{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_implementation : felt
):
    Proxy_only_admin()
    Proxy_set_implementation(new_implementation)
    return ()
end

@external
func addWhitelistedToken{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(lp_token : felt, mint_calculator_address : felt) -> (token_mask : felt):
    alloc_locals
    Ownable_only_owner()
    with_attr error_message("invalid token address"):
        assert_not_zero(lp_token)
    end
    with_attr error_message("invalid oracle address"):
        assert_not_zero(mint_calculator_address)
    end

    different_than_underlying(lp_token)
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)

    with_attr error_message("already whitelisted"):
        assert whitelisted_token.bit_mask = 0
        assert whitelisted_token.mint_calculator_address = 0
    end

    let (tokens_masks : felt) = whitelisted_tokens_mask.read()

    let (token_mask : felt) = get_next_available_bit_in_mask(0, tokens_masks)
    whitelisted_tokens.write(lp_token, WhitelistedToken(token_mask, mint_calculator_address))
    token_mask_addresses.write(token_mask, lp_token)
    let (new_tokens_masks : felt) = bitwise_or(tokens_masks, token_mask)
    whitelisted_tokens_mask.write(new_tokens_masks)
    return (token_mask)
end

@external
func removeWhitelistedToken{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(lp_token : felt):
    Ownable_only_owner()
    let (all_token_masks : felt) = whitelisted_tokens_mask.read()
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(lp_token)
    let (new_tokens_masks : felt) = bitwise_xor(whitelisted_token.bit_mask, all_token_masks)
    whitelisted_tokens_mask.write(new_tokens_masks)

    whitelisted_tokens.write(lp_token, WhitelistedToken(0, 0))
    token_mask_addresses.write(whitelisted_token.bit_mask, 0)
    return ()
end

@external
func setEmergencyBreaker{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    address : felt
):
    Ownable_only_owner()
    assert_not_zero(address)
    emergency_breaker.write(address)
    return ()
end

@external
func deposit{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(assets : Uint256, receiver : felt) -> (shares : Uint256):
    alloc_locals
    ReentrancyGuard_start()
    Pausable_when_not_paused()
    let (default_lock_time : felt) = default_lock_time_days.read()
    let (shares : Uint256) = ERC4626_deposit(assets, receiver, default_lock_time)
    let (underlying_asset : felt) = asset()
    let (default_lock_period : felt) = getDefaultLockTime()
    set_new_deposit_unlock_time(receiver, default_lock_period)
    update_user_after_deposit(receiver, underlying_asset, assets)
    ReentrancyGuard_end()
    return (shares)
end

# `lock_time_days` number of days
@external
func depositForTime{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(assets : Uint256, receiver : felt, lock_time_days : felt) -> (shares : Uint256):
    alloc_locals
    ReentrancyGuard_start()
    Pausable_when_not_paused()
    let (shares : Uint256) = ERC4626_deposit(assets, receiver, lock_time_days)
    set_new_deposit_unlock_time(receiver, lock_time_days)
    let (underlying_asset : felt) = asset()
    update_user_after_deposit(receiver, underlying_asset, assets)
    ReentrancyGuard_end()
    return (shares)
end

# `lock_time_days` number of days
@external
func depositLP{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(lp_token : felt, assets : Uint256, receiver : felt, lock_time_days : felt) -> (shares : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    ReentrancyGuard_start()
    different_than_underlying(lp_token)
    only_whitelisted_token(lp_token)
    set_new_deposit_unlock_time(receiver, lock_time_days)

    let (caller_address : felt) = get_caller_address()
    let (address_this : felt) = get_contract_address()
    let (is_nft : felt) = IERC165.supportsInterface(lp_token, IERC721_ID)

    if is_nft == FALSE:
        let (success : felt) = IERC20.transferFrom(lp_token, caller_address, address_this, assets)
        assert success = TRUE
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
    else:
        let (id_is_zero : felt) = uint256_is_zero(assets)
        with_attr error_message("invalid token id"):
            assert id_is_zero = FALSE
        end
        IERC721.transferFrom(lp_token, caller_address, address_this, assets)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
    end

    let (shares : Uint256) = previewDepositLP(lp_token, assets, lock_time_days)
    ERC20_mint(receiver, shares)
    update_user_after_deposit(receiver, lp_token, shares)
    DepositLP.emit(caller_address, receiver, lp_token, assets, shares)
    ReentrancyGuard_end()
    return (shares)
end

@external
func mint{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(shares : Uint256, receiver : felt) -> (assets : Uint256):
    alloc_locals
    ReentrancyGuard_start()
    Pausable_when_not_paused()
    let (assets : Uint256) = ERC4626_mint(shares, receiver)

    let (underlying_asset : felt) = asset()
    let (default_lock_period : felt) = getDefaultLockTime()
    set_new_deposit_unlock_time(receiver, default_lock_period)
    update_user_after_deposit(receiver, underlying_asset, assets)
    ReentrancyGuard_end()
    return (assets)
end

@external
func redeem{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(shares : Uint256, receiver : felt, owner : felt) -> (assets : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    assert_not_before_unlock_time(owner)
    let (assets : Uint256) = ERC4626_redeem(shares, receiver, owner)
    let (zkp_address : felt) = asset()
    remove_from_deposit(owner, zkp_address, assets)
    return (assets)
end

# lp_token is the LP token address user deposited first and get the xZKP tokens
# shares amount of xZKP tokens user want to redeem
@external
func redeemLP{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(lp_token : felt, shares : Uint256, owner : felt, receiver : felt) -> (amount : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    ReentrancyGuard_start()
    different_than_underlying(lp_token)
    only_whitelisted_token(lp_token)
    assert_not_before_unlock_time(owner)
    let (caller : felt) = get_caller_address()

    if caller != owner:
        decrease_allowance_by_amount(owner, caller, shares)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

    local syscall_ptr : felt* = syscall_ptr
    local pedersen_ptr : HashBuiltin* = pedersen_ptr

    let (address_this : felt) = get_contract_address()
    let (contract_lp_balance : Uint256) = IERC20.balanceOf(lp_token, address_this)
    let (enought_token_balance : felt) = uint256_le(shares, contract_lp_balance)

    if enought_token_balance == FALSE:
        let (amount_to_withdraw : Uint256) = uint256_sub(shares, contract_lp_balance)
        withdraw_from_investment_strategies(lp_token, amount_to_withdraw)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
    end

    ERC20_burn(owner, shares)

    let (lp_withdraw_amount : Uint256) = calculate_withdraw_lp_amount(owner, lp_token, shares)
    remove_from_deposit(owner, lp_token, lp_withdraw_amount)

    let (success : felt) = IERC20.transfer(lp_token, receiver, lp_withdraw_amount)
    assert success = TRUE
    RedeemLP.emit(receiver, owner, lp_token, lp_withdraw_amount, shares)
    ReentrancyGuard_end()
    return (lp_withdraw_amount)
end

@external
func withdraw{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(assets : Uint256, receiver : felt, owner : felt) -> (shares : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    assert_not_before_unlock_time(owner)
    let (shares : Uint256) = ERC4626_withdraw(assets, receiver, owner)
    let (zkp_address : felt) = asset()
    remove_from_deposit(owner, zkp_address, assets)
    return (shares)
end

@external
func withdrawLP{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(lp_token : felt, assets : Uint256, receiver : felt, owner : felt) -> (shares : Uint256):
    alloc_locals
    Pausable_when_not_paused()
    assert_not_before_unlock_time(owner)
    let (caller : felt) = get_caller_address()
    let (shares : Uint256) = previewWithdrawLP(lp_token, assets)
    if caller != owner:
        decrease_allowance_by_amount(owner, caller, shares)
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    else:
        tempvar syscall_ptr = syscall_ptr
        tempvar pedersen_ptr = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
    end

    local syscall_ptr : felt* = syscall_ptr
    local pedersen_ptr : HashBuiltin* = pedersen_ptr

    let (current_xzkp_user_balance) = balanceOf(owner)

    let (output_le : felt) = uint256_le(shares, current_xzkp_user_balance)
    with_attr error_message("invalid xZKP balance"):
        assert output_le = TRUE
    end
    let (user_current_deposit_amount : Uint256) = deposits.read(owner, lp_token)
    let (user_deposit_after_withdraw : Uint256) = uint256_checked_sub_le(
        user_current_deposit_amount, assets
    )
    deposits.write(owner, lp_token, user_deposit_after_withdraw)

    ERC20_burn(owner, shares)
    IERC20.transfer(lp_token, receiver, assets)
    WithdrawLP.emit(caller, receiver, owner, lp_token, assets, shares)
    return (shares)
end

@external
func transfer{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    recipient : felt, amount : Uint256
) -> (success : felt):
    Pausable_when_not_paused()
    let (caller_address : felt) = get_caller_address()
    assert_not_before_unlock_time(caller_address)
    ERC20_transfer(recipient, amount)
    return (TRUE)
end

@external
func transferFrom{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    sender : felt, recipient : felt, amount : Uint256
) -> (success : felt):
    Pausable_when_not_paused()
    assert_not_before_unlock_time(sender)
    ERC20_transferFrom(sender, recipient, amount)
    return (TRUE)
end

@external
func approve{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    spender : felt, amount : Uint256
) -> (success : felt):
    Pausable_when_not_paused()
    let (caller_address : felt) = get_caller_address()
    assert_not_before_unlock_time(caller_address)

    ERC20_approve(spender, amount)
    return (TRUE)
end

@external
func setStakeBoost{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_boost_value : felt
):
    Ownable_only_owner()
    assert_not_zero(new_boost_value)
    lp_stake_boost.write(new_boost_value)
    return ()
end

# new_lock_time number of days
@external
func setDefaultLockTime{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_lock_time_days : felt
):
    alloc_locals
    Ownable_only_owner()
    set_default_lock_time(new_lock_time_days)
    return ()
end

@external
func setFeePercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(fee : felt):
    Ownable_only_owner()
    assert_not_zero(fee)
    fee_percent.write(fee)
    let (caller : felt) = get_caller_address()
    FeePercentUpdated.emit(caller, fee)
    return ()
end

# # @notice Sets a new harvest window.
# # @param newHarvestWindow The new harvest window.
# # @dev HARVEST_DELAY must be set before calling.
@external
func setHarvestWindow{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    window : felt
):
    Ownable_only_owner()
    let (delay) = harvest_delay.read()
    assert_le(window, delay)
    harvest_window.write(window)
    let (caller : felt) = get_caller_address()
    HarvestDelayUpdated.emit(caller, window)
    return ()
end

# # @notice Sets a new harvest delay.
# # @param newHarvestDelay The new harvest delay.
@external
func setHarvestDelay{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_delay : felt
):
    alloc_locals
    Ownable_only_owner()

    let (local delay) = harvest_delay.read()
    assert_not_zero(new_delay)
    assert_le(new_delay, 31536000)  # 31,536,000 = 365 days = 1 year

    let (caller : felt) = get_caller_address()
    # If the previous delay is 0, we should set immediately
    if delay == 0:
        harvest_delay.write(new_delay)
        HarvestDelayUpdated.emit(caller, new_delay)
    else:
        next_harvest_delay.write(new_delay)
        HarvestDelayUpdateScheduled.emit(caller, new_delay)
    end
    return ()
end

# # @notice Sets a new target float percentage.
@external
func setTargetFloatPercent{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    new_float : Uint256
):
    alloc_locals

    Ownable_only_owner()

    uint256_check(new_float)
    let (local lt : felt) = uint256_lt(new_float, Uint256(2 ** 128 - 1, 2 ** 128 - 1))
    assert lt = 1
    target_float_percent.write(new_float)
    let (caller : felt) = get_caller_address()
    TargetFloatPercentUpdated.emit(caller, new_float)
    return ()
end

@external
func pause{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    alloc_locals
    let (caller_address : felt) = get_caller_address()
    let (emergency_breaker_address : felt) = emergency_breaker.read()
    let (owner : felt) = Ownable_get_owner()
    local permissions
    if owner == caller_address:
        permissions = TRUE
    end
    if emergency_breaker_address == caller_address:
        permissions = TRUE  # either owner or emergency breaker have permission to pause the contract
    end
    with_attr error_message("invalid permissions"):
        assert permissions = TRUE
    end
    Pausable_pause()
    return ()
end

@external
func unpause{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}():
    Ownable_only_owner()
    Pausable_unpause()
    return ()
end

#
# Internal
#

func only_whitelisted_token{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    address : felt
):
    let (res : WhitelistedToken) = whitelisted_tokens.read(address)
    with_attr error_message("token not whitelisted"):
        assert_not_zero(res.mint_calculator_address)
        assert_not_zero(res.bit_mask)
    end
    return ()
end

func different_than_underlying{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    address : felt
):
    with_attr error_message("underlying token not allow"):
        let (underlying_asset : felt) = asset()
        assert_not_equal(underlying_asset, address)
    end
    return ()
end

func withdraw_from_investment_strategies{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(lp_token_address : felt, amount : Uint256):
    # TODO: implement
    assert 0 = 1
    return ()
end

# return the first available bit in the mask
func get_next_available_bit_in_mask{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(index : felt, bit_mask : felt) -> (res : felt):
    let (value : felt) = pow(2, index)
    let (and_result : felt) = bitwise_and(value, bit_mask)
    if and_result == 0:
        return (value)
    end

    return get_next_available_bit_in_mask(index + 1, bit_mask)
end

func get_tokens_addresses_from_mask{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(position : felt, bit_mask : felt, tokens_allocation_index : felt, array : felt*) -> (
    length : felt
):
    alloc_locals
    if bit_mask == 0:
        return (tokens_allocation_index)
    end

    let (bit_mask_left : felt, remainder : felt) = unsigned_div_rem(bit_mask, 2)
    if remainder == 1:
        let (token_mask : felt) = pow(2, position)
        let (token_address : felt) = token_mask_addresses.read(token_mask)
        assert [array + tokens_allocation_index] = token_address
        return get_tokens_addresses_from_mask(
            position + 1, bit_mask_left, tokens_allocation_index + 1, array
        )
    end
    return get_tokens_addresses_from_mask(
        position + 1, bit_mask_left, tokens_allocation_index, array
    )
end

func add_token_to_user_mask{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(user : felt, token : felt):
    let (user_current_tokens_mask : felt) = user_staked_tokens.read(user)
    let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(token)
    let (new_user_tokens_mask : felt) = bitwise_or(
        user_current_tokens_mask, whitelisted_token.bit_mask
    )
    user_staked_tokens.write(user, new_user_tokens_mask)
    return ()
end

func assert_not_before_unlock_time{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(user : felt):
    let (current_block_timestamp : felt) = get_block_timestamp()
    let (unlock_time : felt) = deposit_unlock_time.read(user)
    with_attr error_message(
            "timestamp {current_block_timestamp} lower than deposit unlock time {unlock_time}"):
        assert_le(unlock_time, current_block_timestamp)
    end
    return ()
end

func calculate_withdraw_lp_amount{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr
}(owner : felt, lp_token : felt, sharesAmount : Uint256) -> (amount : Uint256):
    return (sharesAmount)
end

func set_new_deposit_unlock_time{syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr}(
    user : felt, lock_time_days : felt
):
    alloc_locals
    let (current_block_timestamp : felt) = get_block_timestamp()
    let (unlock_time : felt) = deposit_unlock_time.read(user)
    let (seconds : felt) = days_to_seconds(lock_time_days)
    with_attr error_message("new deadline should be higher or equal to the old deposit"):
        assert_le(unlock_time, current_block_timestamp + seconds)
    end
    deposit_unlock_time.write(user, current_block_timestamp + seconds)
    return ()
end

# update user deposit info and staked tokens bit mask
func update_user_after_deposit{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(user : felt, token : felt, new_amount : Uint256):
    alloc_locals
    let (current_deposit_amount : Uint256) = deposits.read(user, token)
    let (new_deposit_amount : Uint256) = uint256_checked_add(current_deposit_amount, new_amount)
    deposits.write(user, token, new_deposit_amount)

    let (is_first_deposit : felt) = uint256_is_zero(current_deposit_amount)
    if is_first_deposit == TRUE:
        add_token_to_user_mask(user, token)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        tempvar bitwise_ptr : BitwiseBuiltin* = bitwise_ptr
    else:
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        tempvar bitwise_ptr : BitwiseBuiltin* = bitwise_ptr
    end
    return ()
end

# remove user staked tokens from the bit mask is new balance is 0
func remove_from_deposit{
    syscall_ptr : felt*, pedersen_ptr : HashBuiltin*, range_check_ptr, bitwise_ptr : BitwiseBuiltin*
}(user : felt, token : felt, withdraw_amount : Uint256):
    alloc_locals
    let (current_user_deposit_amount : Uint256) = deposits.read(user, token)
    let (withdraw_all_tokens : felt) = uint256_lt(current_user_deposit_amount, withdraw_amount)
    if withdraw_all_tokens == TRUE:
        deposits.write(user, token, Uint256(0, 0))
        let (user_current_tokens_mask : felt) = user_staked_tokens.read(user)
        let (whitelisted_token : WhitelistedToken) = whitelisted_tokens.read(token)
        let (new_user_tokens_mask : felt) = bitwise_xor(
            user_current_tokens_mask, whitelisted_token.bit_mask
        )
        user_staked_tokens.write(user, new_user_tokens_mask)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar bitwise_ptr : BitwiseBuiltin* = bitwise_ptr
    else:
        let (new_user_deposit_amount : Uint256) = uint256_checked_sub_le(
            current_user_deposit_amount, withdraw_amount
        )
        deposits.write(user, token, new_user_deposit_amount)
        tempvar syscall_ptr : felt* = syscall_ptr
        tempvar pedersen_ptr : HashBuiltin* = pedersen_ptr
        tempvar range_check_ptr = range_check_ptr
        tempvar bitwise_ptr : BitwiseBuiltin* = bitwise_ptr
    end
    return ()
end
