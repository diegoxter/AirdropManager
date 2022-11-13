//SPDX-License-Identifier:UNLICENSE
pragma solidity ^0.8.17;

contract AdminPanel {
    address payable owner;
    uint feeInGwei;

    event EtherWithdrawed(uint256 amount);
    event NewAirdropManagerDeployed(address payable managerOwner, address tokenAddress);

    modifier OnlyOwner() {
        require(msg.sender == owner, 'This can only be done by the owner');
        _;
    }

    constructor(address payable ownerAddress) {
        owner = ownerAddress;
    }

    receive() external payable{
        // to do fix this
        payable(msg.sender).transfer(msg.value);
    }

    fallback() external payable{
        // to do fix this
        payable(msg.sender).transfer(msg.value);
    }

    function newAirdropManagerInstance(address instanceToken) public payable 
    returns (AirdropManager) 
    {
        require(msg.value == feeInGwei, 
            'AdminPanel.newAirdropManagerInstance: You need to deposit the minimum fee');
        AirdropManager newInstance = new AirdropManager(payable(msg.sender), instanceToken);

        emit NewAirdropManagerDeployed(payable(msg.sender), instanceToken);

        return newInstance;
    }

    function withdrawEther() external OnlyOwner {
        // to do optimize this
        uint amountToSend = address(this).balance;
        owner.transfer(amountToSend);

        emit EtherWithdrawed(amountToSend);
    }
}


contract AirdropManager {
    address payable owner;
    address tokenAddress;
    bool public isTokenSet = false;
    uint256 internal lastCampaignID = 0;

    struct AirdropCampaigns {
        uint256 campaignID;
        address campaignAddress;
        bool isCampaignActive;
    }

    // to do events

    modifier OnlyOwner() {
        require(msg.sender == owner, 'This can only be done by the owner');
        _;
    }

    constructor(address payable ownerAddress, address _tokenAddress) {
        owner = ownerAddress;
        tokenAddress = _tokenAddress;
    }
    
    function newAirdropCampaign(address payable instanceOwner, uint endsIn, uint256 amountForCampaign) public OnlyOwner 
    returns (AirdropCampaign) 
    {
        AirdropCampaign newInstance = new AirdropCampaign(instanceOwner, block.timestamp + endsIn);

        require(ERC20(tokenAddress).transferFrom(msg.sender, address(newInstance), amountForCampaign),
            'AirdropManager.newAirdropCampaign: You need to be able to send tokens to the new Campaign');

        // to do send tokens to the new campaign
        emit NewAirdropCampaign()

        return newInstance;
    }

    // to do pause/unpause campaigns

}

contract AirdropCampaign {
    address payable owner;
    bool public acceptPayableWhitelist;
    uint256 public whitelistFee;
    bool public isActive;
    uint256 public claimableSince;
    
    struct Participant {
        address ParticipantAddress;
        bool isBanned;
    }

    mapping(address => Participant) public participantInfo;

    // to do events
    event NewParticipant(address newParticipant);
    event EtherWithdrawed(uint256 amount);

    modifier OnlyOwner() {
        require(msg.sender == owner, 'This can only be done by the owner');
        _;
    }

    /* TO DO
    * manage ERC20 balances 
    * DONE payable whitelist mechanism (with a switch)
    * DONE onlyowner whitelist mechanism
    * DONE receive() add to payable whitelist
    * give tokens to users
    *
    */

    constructor(address payable ownerAddress, uint256 endDate) {
        owner = ownerAddress;
        claimableSince = endDate;
    }

    receive() external payable{
        addToPayableWhitelist();
    }

    fallback() external payable{
        payable(msg.sender).transfer(msg.value);
    }

    function addToPayableWhitelist() public payable {
        require(acceptPayableWhitelist, 
            'AirdropCampaign.addToPayableWhitelist: Payable whitelist is not active');
        require(msg.value == whitelistFee,
            'AirdropCampaign.addToPayableWhitelist: You need to deposit the minimum fee');
        _addToWhitelist(msg.sender);
    }

    function addToWhitelist(address PartAddr) external OnlyOwner{
        _addToWhitelist(PartAddr);
    }

    function _addToWhitelist(address PartAddr) internal {
        require(isActive, 'AirdropCampaign: Campaign inactive');
        require(claimableSince <= block.timestamp, 'AirdropCampaign: Campaign inactive');
        require(participantInfo[PartAddr].ParticipantAddress != PartAddr, 
            'AirdropCampaign._addToWhitelist: Participant already exists');
        participantInfo[PartAddr].ParticipantAddress = PartAddr;
        participantInfo[PartAddr].isBanned = false;

        emit NewParticipant(PartAddr);
    }

    function toggleParticipation(address PartAddr) external OnlyOwner {
        require(participantInfo[PartAddr].ParticipantAddress == PartAddr, 
            "AirdropCampaign._addToWhitelist: Participant doesn't exists");

        if (participantInfo[PartAddr].isBanned == true) {
            participantInfo[PartAddr].isBanned = false;
        } else {
            participantInfo[PartAddr].isBanned = true;
        }
    }

    // to do all this
    bool public testBool;
    function receiveTokens() external {
        require(block.timestamp <= claimableSince, 'AirdropCampaign: Campaign inactive');
        if (testBool == true) {
            testBool = false;
        } else {
            testBool = true;
        }

    }

    function withdrawEther() external OnlyOwner {
        // to do optimize this
        uint amountToSend = address(this).balance;
        owner.transfer(amountToSend);

        emit EtherWithdrawed(amountToSend);
    }
}


interface ERC20 {
    function balanceOf(address owner) external view returns (uint256);
    function allowance(address owner, address spender)
        external
        view
        returns (uint256);
    function approve(address spender, uint256 value) external returns (bool);
    function Mint(address _MintTo, uint256 _MintAmount) external;
    function transfer(address to, uint256 value) external;
    function transferFrom(
        address from,
        address to,
        uint256 value
    ) external returns (bool);
    function totalSupply() external view returns (uint256);
    function CheckMinter(address AddytoCheck) external view returns (uint256);
}