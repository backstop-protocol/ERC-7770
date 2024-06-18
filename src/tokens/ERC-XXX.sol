// SPDX-License-Identifier: GPL-3.0-or-later
pragma solidity ^0.8.13;

import {ERC20} from "@openzeppelin/contracts/token/ERC20/ERC20.sol";

/*pour l'ercxxx @Alfu je pensais tu peux reprendre la logique de ampleforth mais juste pour la clarté au lieu de "gons" et 
de "fragments" tu renommes en "shares" et "underlying". Donc genre dans transfer(address to, uint256 value),  
uint256 gonValue = value.mul(_gonsPerFragment); -> uint256 shareValue = value.mul(_sharesPerUnderlying); 
Et tu peux réutiliser ERC20.balanceOf() au lieu de refaire un storage supplémentaire pour le nombre de shares,
 essayer d'utiliser au max l'ERC20 de base d'openzeppelin. Tu peux checker https://github.com/volt-protocol/ethereum-credit-guild/blob/main/src/tokens/ERC20RebaseDistributor.sol 
 au final c'est le même besoin mais sans interpolation et tout le monde rebase tu as pas de toggle on/off
[08:17]
pour la borrowBlacklist faut que tu gères une "blacklisted supply" qui est un nouveau storage. Quand on ajoute à la blacklist, ++.
 Quand une adresse blacklist reçoit des tokens, (transfer, transferFrom override), ++. Et dans mintForBorrow tu vas utiliser le borrowable -= borrowBlacklistSupply
[08:17]
dans ce que t'as codé vite fait faut aussi décrémenter le borrowable par totalBorrowedSupply parce que sinon ça va pas marcher lol
[08:20]
et je te conseille de faire uen fonction publique rebase(supplyDelta) comme pour ampleforth, pour tes tests, qui appelle juste une 
fonction itnerne _rebase(supplyDelta), et plus tard quand t'auras des repay loan t'auras juste à appeler _rebase(+interest) ou _rebase(-badDebt) pour ajuster le share price, et en attendant tu as une façon easy de tester le reabse (et tu remove la fonction publique plus tard)
[08:20]
pense à bien faire des tests de fuzz parce que les share price c'est bien sournois quand même niveau bugs cachés
Eswak — 06/06/2024 08:22
dans ton implémentation de balanceOf, super.balanceOf(account) (moi j'aurais mis ERC20.balanceOf pour être + clair) c'est ton nombre de shares, et rebaseIndex c'est ton underlyingPerShare, je sais pas si ça t'aide à y réfléchir + clairement*/

contract ERCXXX is ERC20 {
    uint256 public rebaseIndex = 1e18;
    uint256 public totalBorrowedSupply;
    uint256 public maxBorrowSupplyToTotalSupplyRatio;

    /// Token that is held by an address from this list is not borrowable
    /// Relevant only for local tokens: voting contracts, revenue sharing contracts, etc.
    mapping(address => bool) borrowBlacklist;

    constructor(
        string memory _name,
        string memory _symbol
    ) ERC20(_name, _symbol) {}

    /// balanceOf() is multiplied by an index. This is a good reference:
    /// https://github.com/ampleforth/ampleforth-contracts/blob/master/contracts/UFragments.sol#L108
    function balanceOf(address account) public view override returns (uint256) {
        return (super.balanceOf(account) * rebaseIndex) / 1e18;
    }

    function realTotalSupply() public view returns (uint256) {
        return totalSupply() - totalBorrowedSupply;
    }

    function mintForBorrow(address borrower, uint256 amount) public {
        uint256 borrowable = (realTotalSupply() *
            maxBorrowSupplyToTotalSupplyRatio) / 1e18;

        require(
            borrowable >= amount,
            "ERC-XXX: cannot mint, not enough supply"
        );

        totalBorrowedSupply += amount;
        super._mint(borrower, amount);
    }
}
