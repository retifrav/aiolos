# Species file for AU Mic b XUV escape -- atomic hydrogen thermosphere
#
# Column format, as actually read by c_Species::read_species_data (io.cpp:59-76):
# 1:Number 2:Name 3:mass[amu] 4:dof 5:static charge 6:relative amount
# 7:initial density excess 8:is_dust_like 9:opacity file
#
# gamma_adiabat is DERIVED from the dof as (dof+2)/dof, it is NOT read from the
# file, and column 5 is the static charge (floored to an int; nonzero drops the
# species into the Coulomb branch of the friction solver, source.cpp:575-602).
# Hence dof 3 for monatomic H -> gamma = 5/3, and charge 0. Several shipped .spc
# files mislabel column 5 as an adiabatic index and put 1.4 there, which silently
# becomes charge +1 -- do not copy that.
# Columns 8 and 9 are mandatory: a short row is an unchecked read past the end of
# the token vector and segfaults or exits 5 with nothing pointing at this file.
#
# WHY ATOMIC H AND NOT H2 + He
#   This is a single-species model of the XUV-heated THERMOSPHERE, above the
#   homopause, where H2 is photodissociated. Substituting H2 (2.016 amu, dof 5)
#   breaks the setup in two independent ways, both verified:
#     - the scale height H = kT/(m g) halves, so with cells_per_decade 500 the
#       grid falls below one cell per scale height, the hydrostatic construction
#       undershoots onto the density_floor * (r/r1)^-4 profile after ~20 cells,
#       and the remaining ~977 cells -- which that floor leaves ~74x
#       under-supported against gravity -- free-fall. dt collapses to ~1e-15 s
#       and the temperature goes NaN.
#     - gamma drops from 5/3 to 1.4, lowering the sound speed by 1.55x and
#       pushing GM/cs^2 from 14 Rp out to 34 Rp, i.e. outside the domain, so no
#       transonic solution exists anywhere on the grid.
#   If you need the H2 -> H dissociation front itself, that is a multi-species
#   photochemistry problem (c2ray/*.par, PHOTOCHEM_LEVEL 1, 3 species), not a
#   single-species run.
#
# Column 7 (initial density excess) is 0.0 deliberately. The shipped
# mix_static_paperplot.spc uses -0.9999, which multiplies the density by 1e-4
# above the sonic radius to seed an outflow (init_and_bounds.cpp:1648-1669,
# active only under PARI_INIT_WIND 1). Tested here: it makes no difference at all
# -- the converged mass-loss rate is identical to 5 significant figures -- so the
# clean value is kept rather than the inherited magic number.
#
@ 0  H  1.008  3.  0.  1.0  0.0  0  highenergy3.opa
