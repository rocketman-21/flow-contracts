// SPDX-License-Identifier: MIT
pragma solidity ^0.8.28;

import { FlowTCRTest } from "./FlowTCR.t.sol";
import { FlowTypes } from "../../src/storage/FlowStorageV1.sol";
import { IArbitrator } from "../../src/tcr/interfaces/IArbitrator.sol";
import { IArbitrable } from "../../src/tcr/interfaces/IArbitrable.sol";
import { IERC20 } from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { IGeneralizedTCR } from "../../src/tcr/interfaces/IGeneralizedTCR.sol";
import { IERC721Flow } from "../../src/interfaces/IFlow.sol";
import { NounsFlow } from "../../src/NounsFlow.sol";
import { RewardPool } from "../../src/RewardPool.sol";
import { Flow } from "../../src/Flow.sol";
import { IFlow } from "../../src/interfaces/IFlow.sol";
import { Strings } from "@openzeppelin/contracts/utils/Strings.sol";
import { ERC1967Proxy } from "@openzeppelin/contracts/proxy/ERC1967/ERC1967Proxy.sol";

contract TCRFundFlowTest is FlowTCRTest {
    // add 4 items, vote and execute using requester

    function test_issue() public {
        vm.createSelectFork("https://mainnet.base.org", 21347817);

        address deployedFlow = address(0x816897059Ce5938C16A2770Bf9BA9A7caA487639);

        address nounsFlowImpl = address(new NounsFlow());
        // upgrade flow to current implementation
        vm.prank(0x289715fFBB2f4b482e2917D2f183FeAb564ec84F);
        Flow(deployedFlow).upgradeTo(nounsFlowImpl);

        // set flow rate to 1000000
        vm.prank(0x289715fFBB2f4b482e2917D2f183FeAb564ec84F);
        IFlow(deployedFlow).setFlowRate(3858024691358);

        vm.prank(0x289715fFBB2f4b482e2917D2f183FeAb564ec84F);
        IFlow(deployedFlow).setFlowRate(3858024691358 / 2);

        vm.prank(0x289715fFBB2f4b482e2917D2f183FeAb564ec84F);
        Flow(deployedFlow).setManagerRewardFlowRatePercent(200000);
    }
}
