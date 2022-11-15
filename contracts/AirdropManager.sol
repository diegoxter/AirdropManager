//SPDX-License-Identifier:UNLICENSE
pragma solidity ^0.8.17;

contract AdminPanel {
    address payable public owner;
    uint public feeInGwei;
    AirManInstance[] public deployedManagers;

    struct AirManInstance {
        address owner;
        address instanceAddress;
        address instanceToken;
    }

    event EtherWithdrawed(uint256 amount);
    event NewAirdropManagerDeployed(address payable managerOwner, address tokenAddress);

    modifier OnlyOwner() {
        require(msg.sender == owner, 'This can only be done by the owner');
        _;
    }

    constructor(uint256 _feeInGwei) {
        owner = payable(msg.sender);
        feeInGwei = _feeInGwei;
    }

    receive() external payable{
        // to do fix this
        payable(msg.sender).transfer(msg.value);
    }

    fallback() external payable{
        // to do fix this
        payable(msg.sender).transfer(msg.value);
    }

    function newAirdropManagerInstance(address instanceToken, uint256 initialBalance) public payable 
    returns (AirdropManager) 
    {
        require(msg.value == feeInGwei, 
            'AdminPanel.newAirdropManagerInstance: You need to deposit the minimum fee');
        require(ERC20(instanceToken).transferFrom(msg.sender, address(this), initialBalance),
            'AirdropManager.newAirdropManagerInstance: You need to be able to send tokens to the new Campaign');    
        
        AirdropManager newInstance = new AirdropManager(payable(msg.sender), instanceToken);
        ERC20(instanceToken).transfer(address(newInstance), initialBalance);

        deployedManagers.push(
            AirManInstance({
                owner: msg.sender,
                instanceAddress: address(newInstance),
                instanceToken: instanceToken
            })
        );

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
    address payable public owner;
    address public tokenAddress;
    uint256 internal lastCampaignID = 0;
    Campaign[] public campaigns;

    struct Campaign {
        uint256 campaignID;
        uint256 endDate;
        AirdropCampaign campaignAddress;
        uint256 amountToAirdrop;
        bool isCampaignActive;
        bool fixedAmount;
        uint256 amountForEachUser; // can be 0
    }

    event NewAirdropCampaign(uint256 endsIn, uint256 amountToAirdrop);

    modifier OnlyOwner() {
        require(msg.sender == owner, 'This can only be done by the owner');
        _;
    }

    constructor(address payable ownerAddress, address _tokenAddress) {
        owner = ownerAddress;
        tokenAddress = _tokenAddress;
    }
    
    function newAirdropCampaign(uint endsIn, uint256 amountForCampaign, bool hasFixedAmount, uint256 amountForEveryUser) public OnlyOwner 
    returns (AirdropCampaign) 
    {
        require(amountForCampaign <= ERC20(tokenAddress).balanceOf(address(this)),
            'AirdropManager.newAirdropCampaign: Not enought tokens to fund this campaign');
        AirdropCampaign newInstance = 
            new AirdropCampaign(payable(address(this)), block.timestamp + endsIn, tokenAddress, hasFixedAmount, amountForEveryUser);

        ERC20(tokenAddress).transfer(address(newInstance), amountForCampaign);

        campaigns.push(
            Campaign({
                campaignID: lastCampaignID,
                endDate: block.timestamp + endsIn,
                campaignAddress: newInstance,
                amountToAirdrop: amountForCampaign,
                isCampaignActive: true,
                fixedAmount: hasFixedAmount,
                amountForEachUser: amountForEveryUser
            })
        );
        
        AirdropCampaign(campaigns[lastCampaignID].campaignAddress).updateTokenBalance();

        lastCampaignID++;

        emit NewAirdropCampaign(endsIn, amountForCampaign);

        return newInstance;
    }

    function batchAddToWhitelist(uint256 campaignID, address[] memory PartAddr) external OnlyOwner{
        AirdropCampaign(campaigns[campaignID].campaignAddress).batchAddToWhitelist(PartAddr);
    }

    function toggleCampaign(uint256 campaignID) external OnlyOwner {
        require(campaignID <= lastCampaignID, 
            'AirdropManager.toggleCampaign: This campaign ID does not exist');
        AirdropCampaign(campaigns[campaignID].campaignAddress).toggleIsActive();
        campaigns[campaignID].isCampaignActive = 
            AirdropCampaign(campaigns[campaignID].campaignAddress).isActive();    
    }

    function togglePayableWhitelist(uint256 campaignID) external OnlyOwner {
        require(campaignID <= lastCampaignID, 
            'AirdropManager.toggleCampaign: This campaign ID does not exist');
        AirdropCampaign(campaigns[campaignID].campaignAddress).togglePayableWhitelist();  
    }

    // to do add the other switches here

    function toggleParticipation(uint256 campaignID, address PartAddr) external OnlyOwner {
        require(campaignID <= lastCampaignID, 
            'AirdropManager.toggleParticipation: This campaign ID does not exist');
        AirdropCampaign(campaigns[campaignID].campaignAddress).toggleParticipation(PartAddr);
    }
}

contract AirdropCampaign {
    address payable owner;
    address tokenAddress;
    bool public acceptPayableWhitelist = false;
    uint256 public whitelistFee;
    uint256 public participantAmount = 0;
    bool public fixedAmount;
    uint256 public amountForEachUser;
    uint256 public tokenBalance;
    bool public isActive;
    uint256 public claimableSince;
    
    struct Participant {
        address ParticipantAddress;
        bool canReceive;
        bool claimed;
    }

    mapping(address => Participant) public participantInfo;

    // to do events
    event CampaignStatusToggled(string optionToggled, bool isActive_);
    event NewParticipant(address newParticipant);
    event EtherWithdrawed(uint256 amount);
    event TokenClaimed(address participantAddress, uint256 claimed);
    event UserParticipationToggled(address participantAddress, bool isBanned);

    modifier OnlyOwner() {
        require(msg.sender == owner, 'This can only be done by the owner');
        _;
    }

    constructor(
        address payable ownerAddress, 
        uint256 endDate, 
        address _tokenAddress, 
        bool hasFixedAmount,
        uint256 valueForEachUser  // can be 0
    ) 
    {
        owner = ownerAddress;
        tokenAddress = _tokenAddress;
        claimableSince = endDate;
        isActive = true;
        fixedAmount = hasFixedAmount;

        if (hasFixedAmount) 
            amountForEachUser = valueForEachUser;
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

    function batchAddToWhitelist(address[] memory PartAddr) external OnlyOwner{
        for (uint256 id = 0; id < PartAddr.length; ++id) {
            _addToWhitelist(PartAddr[id]);
        }
    }

    function updateTokenBalance() external OnlyOwner{
        tokenBalance = ERC20(tokenAddress).balanceOf(address(this));
    }

    function _addToWhitelist(address PartAddr) internal {
        require(isActive, 'AirdropCampaign._addToWhitelist: Campaign inactive');
        require(block.timestamp <= claimableSince, 'AirdropCampaign._addToWhitelist: Campaign time ended');
        require(participantInfo[PartAddr].ParticipantAddress != PartAddr, 
            'AirdropCampaign._addToWhitelist: Participant already exists');
        participantInfo[PartAddr].ParticipantAddress = PartAddr;
        participantInfo[PartAddr].canReceive = true;
        participantInfo[PartAddr].claimed = false;

        participantAmount++;

        emit NewParticipant(PartAddr);
    }

    function toggleParticipation(address PartAddr) external OnlyOwner {
        require(block.timestamp <= claimableSince, 'AirdropCampaign.toggleIsActive: Can not modify users, time is up');
        require(participantInfo[PartAddr].ParticipantAddress == PartAddr, 
            "AirdropCampaign.toggleParticipation: Participant doesn't exists");

        if (participantInfo[PartAddr].canReceive == true) {
            participantInfo[PartAddr].canReceive = false;
            participantAmount--;
        } else {
            participantInfo[PartAddr].canReceive = true;
            participantAmount++;
        }

        emit UserParticipationToggled(PartAddr, participantInfo[PartAddr].canReceive);
    }

    function toggleIsActive() external OnlyOwner {
        require(block.timestamp <= claimableSince, 'AirdropCampaign.toggleIsActive: Can not modify status, time is up');

        if (isActive == true) {
            isActive = false;
        } else {
            isActive = true;
        }

        emit CampaignStatusToggled('Is Campaign active?', isActive);
    }

    function togglePayableWhitelist() external OnlyOwner {
        if (acceptPayableWhitelist == true) {
            acceptPayableWhitelist = false;
        } else {
            acceptPayableWhitelist = true;
        }

        emit CampaignStatusToggled('Does Campaign accepts Payable Whitelist?', acceptPayableWhitelist);
    }

    // to do all this
    function receiveTokens() external {
        require(block.timestamp >= claimableSince, 'AirdropCampaign: Airdrop still not claimable');
        require(participantInfo[msg.sender].canReceive == true, 'AirdropCampaign: You can not claim this airdrop');
        require(participantInfo[msg.sender].claimed == false, 
            'AirdropCampaign: You already claimed your tokens');

        uint256 _ToSend;
        if (fixedAmount) {
            _ToSend = amountForEachUser;
        } else {
            _ToSend = tokenBalance / participantAmount;
        }

        participantInfo[msg.sender].claimed = true;
        ERC20(tokenAddress).transfer(msg.sender, _ToSend);

        emit TokenClaimed(msg.sender, _ToSend);
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