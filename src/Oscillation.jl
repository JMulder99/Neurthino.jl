struct OscillationParameters
    dim::Integer
    mixing_angles::UnitUpperTriangular{T, <: AbstractMatrix{T}} where {T <: Real}
    mass_squared_diff::UnitUpperTriangular{T, <: AbstractMatrix{T}} where {T <: Real}
    cp_phases::UnitUpperTriangular{T, <: AbstractMatrix{T}} where {T <: Real}

    OscillationParameters(dim::Integer) = begin
            new(dim,
                UnitUpperTriangular(zeros(Float64, (dim, dim))),
                UnitUpperTriangular(zeros(Float64, (dim, dim))),
                UnitUpperTriangular(zeros(Float64, (dim, dim))))
    end
end

function _generate_ordered_index_pairs(n::Integer)
    number_of_angles = number_mixing_angles(n)
    indices = Vector{Pair{Int64,Int64}}(undef, number_of_angles)
    a = 1
    for i in 1:n 
        for j in 1:i-1
            indices[a] = Pair(j,i)
            a += 1
        end
    end
    indices
end

"""
    MatterOscillationMatrices(osc_params::OscillationParameters, matter_density)

Create modified oscillation parameters for neutrino propagation through matter

# Arguments
- `osc_vacuum::OscillationParameters`: Oscillation parameters in vacuum
- `matter_density`: Matter density in g*cm^-3 

"""
function MatterOscillationMatrices(osc_vacuum::OscillationParameters, matter_density)
    H_vacuum = Diagonal(Hamiltonian(osc_vacuum)) 
    U_vacuum = PMNSMatrix(osc_vacuum)
    return MatterOscillationMatrices(H_vacuum, U_vacuum, matter_density)
end

"""
    MatterOscillationMatrices(U_vac, H_vac, matter_density)

Create modified oscillation parameters for neutrino propagation through matter

# Arguments
- `U_vac`: Vacuum PMNSMatrix
- `H_vac`: Vacuum Hamiltonian
- `matter_density`: Matter density in g*cm^-3 

"""
function MatterOscillationMatrices(U_vac, H_vac, matter_density)
    H_flavour = Array{Complex}(U_vac * Diagonal(H_vac) * adjoint(U_vac))
    A = 2 * sqrt(2) * ustrip(G_F) * ustrip(PhysicalConstants.CODATA2018.AvogadroConstant) * 1e9
    A *= matter_density
    H_flavour[1,1] += A  
    U_matter = eigvecs(H_flavour)
    H_matter = eigvals(H_flavour)
    return H_matter, U_matter
end

function PMNSMatrix(osc_params::OscillationParameters)
"""
    PMNSMatrix(osc_params::OscillationParameters)

Create rotation matrix (PMNS) based on the given oscillation parameters

# Arguments
- `osc_params::OscillationParameters`: Oscillation parameters

"""
    pmns = Matrix{Complex}(1.0I, osc_params.dim, osc_params.dim) 
    indices = _generate_ordered_index_pairs(osc_params.dim)
    for (i, j) in indices
        rot = sparse((1.0+0im)I, osc_params.dim, osc_params.dim) 
        mixing_angle = osc_params.mixing_angles[i, j]
        c, s = cos(mixing_angle), sin(mixing_angle)
        rot[i, i] = c
        rot[j, j] = c
        rot[i, j] = s
        rot[j, i] = -s
        if CartesianIndex(i, j) in findall(!iszero, osc_params.cp_phases)
            cp_phase = osc_params.cp_phases[i, j]
            cp_term = exp(-1im * cp_phase)
            rot[i, j] *= cp_term
            rot[j, i] *= conj(cp_term)
        end
        pmns = rot * pmns 
    end
    pmns
end

function Hamiltonian(osc_params::OscillationParameters)
"""
    Hamiltonian(osc_params::OscillationParameters)

Create modified hamiltonian matrix consisting of the squared mass differences
based on the given oscillation parameters

# Arguments
- `osc_params::OscillationParameters`: Oscillation parameters

"""
    Hamiltonian(osc_params, zeros(Float64, osc_params.dim))
end 

function Hamiltonian(osc_params::OscillationParameters, lambda)
"""
    Hamiltonian(osc_params::OscillationParameters)

Create modified hamiltonian matrix consisting of the squared mass differences
based on the given oscillation parameters

# Arguments
- `osc_params::OscillationParameters`:  Oscillation parameters
- `lambda`:                             Decay parameters for each mass eigenstate

"""
    H = zeros(Complex, osc_params.dim)
    for i in 1:osc_params.dim
        for j in 1:osc_params.dim
            if i < j
                H[i] += osc_params.mass_squared_diff[i,j]
            elseif j < i
                H[i] -= osc_params.mass_squared_diff[j,i]
            end
        end
        H[i] += 1im * lambda[i]
    end
    H /= osc_params.dim
    H
end


"""
    transprob(U, H, energy, baseline)

Calculate the transistion probability between the neutrino flavours

# Arguments
- `U`:          Unitary transition matrix
- `H`:          Energy eigenvalues
- `energy`:     Baseline [km]
- `baseline`:   Energy [GeV]

"""
function transprob(U, H, energy, baseline)  
    H_diag = 2.534 * Diagonal(H) * baseline / energy 
    A = U * exp(-1im * H_diag) * adjoint(U)
    P = abs.(A) .^ 2
end

"""
    transprob(osc_params::OscillationParameters, energy, baseline)

Calculate the transistion probability between the neutrino flavours

# Arguments
- `osc_params::OscillationParameters`:  Oscillation parameters
- `energy`:                             Baseline [km]
- `baseline`:                           Energy [GeV]

"""
function transprob(osc_params::OscillationParameters, energy, baseline)  
    H = Hamiltonian(osc_params)
    U = PMNSMatrix(osc_params)
    H_diag = 2.534 * Diagonal(H) * baseline / energy 
    A = U * exp(-1im * H_diag) * adjoint(U)
    P = abs.(A) .^ 2
end

"""
    number_cp_phases(n::Unsigned)

Returns the number of CP violating phases at given number of neutrino types

# Arguments
- `n::Unsigned`: number of neutrino types in the supposed model

# Examples
```julia-repl
julia> Neurthino.number_cp_phases(3)
1
```
"""
function number_cp_phases(n::T) where {T <: Integer}
    if (n < 1) return 0 end
    cp_phases = div( (n-1)*(n-2) , 2 )
end

"""
    number_mixing_angles(n::Unsigned)

Returns the number of mixing angles at given number of neutrino types

# Arguments
- `n::Unsigned`: number of neutrino types in the supposed model

# Examples
```julia-repl
julia> Neurthino.number_mixing_phases(3)
3
```
"""
function number_mixing_angles(n::T) where {T <: Integer}
    if (n < 1) return 0 end
    mixing_angles = div( n*(n-1) , 2 )
end
