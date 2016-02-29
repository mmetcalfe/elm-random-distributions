module Random.Distributions (normal) where

{-| This library provides standard non-uniform random sampling methods for the
core Random library.

# Distributions implemented
@docs normal

-}

import Random

{-| The error function
Approximation with a maximal error of 1.2*10^-7.

Directly from wikipedia:
https://en.wikipedia.org/wiki/Error_function#Numerical_approximation

\begin{align}
\tau = {} & t\cdot\exp\left(-x^2-1.26551223+1.00002368 t+0.37409196 t^2+0.09678418 t^3\right.\\
& \left.{}-0.18628806 t^4+0.27886807 t^5-1.13520398 t^6+1.48851587\cdot t^7\right. \\
& \left.{}-0.82215223 t^8+0.17087277 t^9\right)
\end{align}
-}
erf x =
  let
    t = 1 / (1 + 0.5 * abs x)
    exponent =
      -x^2
      - 1.26551223
      + 1.00002368 * t
      + 0.37409196 * t^2
      + 0.09678418 * t^3
      - 0.18628806 * t^4
      + 0.27886807 * t^5
      - 1.13520398 * t^6
      + 1.48851587 * t^7
      - 0.82215223 * t^8
      + 0.17087277 * t^9
    tau = t * e ^ exponent
    y =
      if x >= 0
        then 1 - tau
        else tau + 1
  in
    clamp 0 1 y

{-| The complimentary error function
Approximation with a maximal error of 1.2*10^-7.
-}
erfc x = clamp 0 1 (1 - erf x)

{-| The natural logarithm
-}
ln x = logBase e x

probability : Random.Generator Float
probability =
  Random.float 0 1

{-| A `random' generator that always returns the given value.
-}
identityGenerator : Float -> Random.Generator Float
identityGenerator x =
  Random.map (always x) Random.bool

-- probabilities : Generator (Float, Float)
-- probabilities = pair probability probability

normalDensity mu sigma x =
  let
    factor = 1 / (sigma * sqrt (2*pi))
    exponent = -(x-mu)^2 / (2*sigma^2)
  in
    factor * e ^ exponent

normalDensityInverse mu sigma y =
  let
    factor = 1 / (sigma * sqrt (2*pi))
  in
    mu + sqrt (-2 * sigma^2 * ln (y / factor))

{-| Find x1 and A for a given table size, density function, and inverse density
function.

https://en.wikipedia.org/wiki/Ziggurat_algorithm#Finding_x1_and_A
-}
zigguratX1 : Int -> (Float -> Float) -> (Float -> Float) -> Float
zigguratX1 n pFunc invPFunc =
  let
    f0 = pFunc 0
    areaDiffFunc x1 =
      let
        y1 = pFunc x1
        tailArea = erfc x1
        baseLayerArea = x1*y1 + tailArea
        tables = zigguratTables n y1 baseLayerArea pFunc invPFunc
        (xn_1, yn_1) =
          case List.head <| List.drop (n-1) <| tables of
            Just pair -> pair
            Nothing -> Debug.crash "The list tables was not of length n"
        topLayerArea = xn_1*(f0 - yn_1)
      in
        topLayerArea - baseLayerArea
    x1 =
      case bisectionSearch areaDiffFunc 1e-5 100 0 100 of
        Just v -> v
        Nothing -> Debug.crash "The bisectionSearch failed"
  in
    x1

{-| Bisection method for root finding

https://en.wikipedia.org/wiki/Bisection_method
-}
bisectionSearch : (Float -> Float) -> Float -> Int -> Float -> Float -> Maybe Float
bisectionSearch f eps n a b =
  let
    sign x =
      if x > 0
        then 1
        else -1
    search n a b =
      let
        va = f a
        vb = f b
      in
        if n <= 0 || sign va == sign vb
          then Nothing
          else
            let
              c = (a + b) / 2
              vc = f c
            in
              if vc == 0 || (b - a) / 2 < eps
                then Just c
                else
                  if sign vc == sign va
                    then search (n-1) c b
                    else search (n-1) a c
  in
    if a < b
      then search n a b
      else search n b a


{-| Generate the ziggurat tables

https://en.wikipedia.org/wiki/Ziggurat_algorithm#Generating_the_tables
-}
zigguratTables : Int -> Float -> Float -> (Float -> Float) -> (Float -> Float) -> List (Float, Float)
zigguratTables n y1 layerArea pFunc invPFunc =
  let
    x1 = invPFunc y1
    nextLayer (xi, yi) =
      let
        yi1 = yi + layerArea / xi
        xi1 = invPFunc yi1
      in (xi1, yi1)
  in
    List.scanl (\_ x1y1 -> nextLayer x1y1) (x1, y1) [1..n]

{-| Implement the Ziggurat algorithm for one-sided distributions.

https://en.wikipedia.org/wiki/Ziggurat_algorithm
-}
ziggurat pFunc tailFallback = Random.float 0 1
--   let n =


tableSize = 256
normalZigguratTables =
  let
    n = tableSize
    pFunc = normalDensity 0 1
    invPFunc = normalDensityInverse 0 1
    x1 = zigguratX1 n pFunc invPFunc
    y1 = pFunc x1
    tailArea = erfc x1
    layerArea = x1*y1 + tailArea
  in
    zigguratTables n y1 layerArea pFunc invPFunc


{-| Fallback algorithm for the tail of a normal distribution

From wikipedia: https://en.wikipedia.org/wiki/Ziggurat_algorithm

For a normal distribution, Marsaglia suggests a compact algorithm:
  1.  Let x = −ln(U1)/x1.
  2.  Let y = −ln(U2).
  3.  If 2y > x^2, return x + x1.
  4.  Otherwise, go back to step 1.
-}
zigguratNormalTail x1 =
  let
    u1u2gen = Random.pair probability probability
    fallback (u1, u2) =
      let
        x = -(ln u1)/x1
        y = -(ln u2)
      in
        if 2*y > x^2
          then identityGenerator (x + x1)
          else zigguratNormalTail x1
  in
    u1u2gen `Random.andThen` fallback

{-| Generate a standard normal distribution using the Ziggurat algorithm.

https://en.wikipedia.org/wiki/Ziggurat_algorithm

-}
normal : Random.Generator Float
-- normal = ziggurat <| normalDensity 0 1
normal = zigguratNormalTail 3.5
