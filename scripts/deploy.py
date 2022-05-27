import os

from nile.nre import NileRuntimeEnvironment

# Dummy values, should be replaced by env variables
os.environ["SIGNER"] = "123456"
os.environ["USER_1"] = "12345654321"


def to_uint(a):
    """Takes in value, returns uint256-ish tuple."""
    return (a & ((1 << 128) - 1), a >> 128)


def str_to_felt(text):
    b_text = bytes(text, "ascii")
    return int.from_bytes(b_text, "big")


INITIAL_SUPPLY = "10000000000000000000000"
MAX_SUPPLY = "100000000000000000000000000"
DECIMALS = "18"
NAME = str_to_felt("ZkPad")
SYMBOL = str_to_felt("ZKP")

XZKP_NAME = str_to_felt("xZkPad")
XZKP_SYMBOL = str_to_felt("xZKP")

REWARDS_PER_BLOCK = to_uint(10)
START_BLOCK = 0
END_BLOCK = START_BLOCK + 10000


def run(nre: NileRuntimeEnvironment):
    signer = nre.get_or_deploy_account("SIGNER")
    user_1 = nre.get_or_deploy_account("USER_1")
    print(f"Signer account: {signer.address}")
    print(f"User1 account: {user_1.address}")

    # Deploy ZKP token
    zkp_token = None
    try:
        zkp_token, abi = nre.deploy("ZkPadToken", arguments=[
            str(NAME),
            str(SYMBOL),
            DECIMALS,
            INITIAL_SUPPLY,
            "0",
            "0x970e62cb92ae24fb6f1ea455407edf6cb0f3b739940b4dffbf976b65d7830a",
            signer.address,
            MAX_SUPPLY,
            "0",
            user_1.address  # distribution address
        ], alias="zkp_token")

    except Exception as error:
        if "already exists" in str(error):
            zkp_token, abi = nre.get_deployment("zkp_token")
        else:
            print(f"DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Deployed ZKP token to {zkp_token}")

    # Deploy xZKP
    xzkp_token = None
    xzkp_token_implementation = None
    try:
        xzkp_token_implementation, abi = nre.deploy(
            "ZkPadStaking", alias="xzkp_token_implementation")
    except Exception as error:
        if "already exists" in str(error):
            xzkp_token_implementation, _ = nre.get_deployment(
                "xzkp_token_implementation")
        else:
            print(f"DEPLOYMENT ERROR: {error}")
    finally:
        print(
            f"xZKP token implementation deployed to {xzkp_token_implementation}")

    try:
        xzkp_token, _ = nre.deploy(
            "OZProxy",
            arguments=[xzkp_token_implementation],
            alias="xzkp_token_proxy")
    except Exception as error:
        if "already exists" in str(error):
            xzkp_token, _ = nre.get_deployment("xzkp_token_proxy")
        else:
            print(f"DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Deployed xZKP token proxy to {xzkp_token}")

    signer.send(xzkp_token, "initializer", calldata=[
        str(XZKP_NAME),
        str(XZKP_SYMBOL),
        int(zkp_token, 16),
        int(signer.address, 16),
        *REWARDS_PER_BLOCK,
        START_BLOCK,
        END_BLOCK
    ])
    print("xZKP token proxy initialized")

    harvest_task_contract = None
    try:
        harvest_task_contract, _ = nre.deploy("ZkPadVaultHarvestTask", arguments=[xzkp_token], alias="harvest_task")
    except Exception as error:
        if "already exists" in str(error):
            harvest_task_contract, _ = nre.get_deployment("harvest_task")
        else:
            print(f"DEPLOYMENT ERROR: {error}")
    finally:
        print(f"Deployed harvest task contract to {xzkp_token}")

    signer.send(xzkp_token, "setHarvestTaskContract", calldata=[int(harvest_task_contract, 16)])
