import os
import sys
from nile.nre import NileRuntimeEnvironment

sys.path.append(os.path.dirname(__file__))
from utils import deploy_try_catch, run_tx

# Dummy values, should be replaced by env variables
# os.environ["SIGNER"] = "123456"
# os.environ["USER_1"] = "12345654321"


def to_uint(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


def str_to_felt(text):
    b_text = bytes(text, "ascii")
    return int.from_bytes(b_text, "big")


def run(nre: NileRuntimeEnvironment):
    signer = nre.get_or_deploy_account("SIGNER")
    user_1 = nre.get_or_deploy_account("USER_1")
    print(f"Signer account: {signer.address}")
    print(f"User1 account: {user_1.address}")

    xzkp_token, _ = nre.get_deployment("xzkp_token_proxy")

    # Deploy AlphaRoad Wrapper  
    alpha_road_pool = "0x68f02f0573d85b5d54942eea4c1bf97c38ca0e3e34fe3c974d1a3feef6c33be"
    alpha_road = deploy_try_catch(nre, "AlphaRoadWrapper", [alpha_road_pool], "alpha_road")

    run_tx(signer, xzkp_token, "addWhitelistedToken", [
           int(alpha_road_pool, 16), int(alpha_road, 16), False])

    # Deploy JediSwap Wrapper
    jedi_swap_pool = "0x68f02f0573d85b2d54942eea4c1bf97c38ca0e3e34fe3c974d1a3feef6c33be"
    jedi_swap = deploy_try_catch(nre, "JediSwapWrapper", [jedi_swap_pool], "jedi_swap")

    run_tx(signer, xzkp_token, "addWhitelistedToken", [
           int(jedi_swap_pool, 16), int(jedi_swap, 16), False])

    

