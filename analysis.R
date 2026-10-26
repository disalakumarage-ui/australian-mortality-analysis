install.packages("tidyverse")   # only need to run this once
library(tidyverse)

# Load the data
mx <- read_table("Mx_1x1.txt", skip = 2, na = ".") |>
  mutate(Age = as.integer(str_remove(Age, "\\+")))

# Plot death rates by age for three years
mx |>
  filter(Year %in% c(1970, 1995, 2020), Age <= 100) |>
  ggplot(aes(Age, Male, colour = factor(Year))) +
  geom_line(linewidth = 1) +
  scale_y_log10() +
  labs(title = "Australian male mortality rates",
       y = "Death rate (log scale)", colour = "Year") +
  theme_minimal()

# Build life tables for every year since 1970, males and females
life_exp <- mx |>
  select(Year, Age, Female, Male) |>
  pivot_longer(c(Female, Male), names_to = "Sex", values_to = "mx") |>
  filter(Year >= 1970) |>
  arrange(Sex, Year, Age) |>
  group_by(Sex, Year) |>
  mutate(
    qx = pmin(mx / (1 + 0.5 * mx), 1),                   # prob. of dying within the year
    qx = if_else(is.na(qx) | Age == max(Age), 1, qx),    # everyone dies by the last age
    lx = 100000 * lag(cumprod(1 - qx), default = 1),     # survivors out of 100,000
    dx = lx * qx,                                        # deaths at each age
    Lx = lx - 0.5 * dx,                                  # person-years lived at each age
    Tx = rev(cumsum(rev(Lx))),                           # total years remaining
    ex = Tx / lx                                         # life expectancy
  ) |>
  ungroup()

# Check: life expectancy in 2020
life_exp |> filter(Year == 2020, Age %in% c(0, 65)) |> select(Sex, Age, ex)

# Plot life expectancy at birth and at 65 over time
life_exp |>
  filter(Age %in% c(0, 65)) |>
  ggplot(aes(Year, ex, colour = Sex)) +
  geom_line(linewidth = 1) +
  facet_wrap(~ Age, scales = "free_y",
             labeller = labeller(Age = c(`0` = "At birth", `65` = "At age 65"))) +
  labs(title = "Australian life expectancy since 1970",
       y = "Years of life remaining", x = NULL) +
  theme_minimal()

# Fit Gompertz (mx = B * c^Age) to 2020 male rates, ages 30–90
fit_data <- mx |> filter(Year == 2020, Age >= 30, Age <= 90)
gompertz <- lm(log(Male) ~ Age, data = fit_data)

B     <- exp(coef(gompertz)[1])
c_par <- exp(coef(gompertz)[2])
B; c_par
summary(gompertz)$r.squared

# Observed vs fitted across all ages
mx |>
  filter(Year == 2020, Age <= 100) |>
  mutate(fitted = B * c_par^Age) |>
  ggplot(aes(Age)) +
  geom_point(aes(y = Male), size = 1) +
  geom_line(aes(y = fitted), colour = "red", linewidth = 1) +
  scale_y_log10() +
  labs(title = "Gompertz fit to 2020 Australian male mortality",
       subtitle = "Fitted on ages 30–90",
       y = "Death rate (log scale)") +
  theme_minimal()

lt <- life_exp |> filter(Sex == "Male", Year == 2020) |> select(Age, qx, lx)

# Whole-life annuity: value of $1/year paid from age x until death
annuity <- function(x, i) {
  t <- lt |> filter(Age >= x)
  kpx <- t$lx / t$lx[1]                      # prob. of surviving k years
  sum((1 / (1 + i))^(0:(nrow(t) - 1)) * kpx)
}

# n-year annuity (used for paying premiums)
temp_annuity <- function(x, n, i) {
  t <- lt |> filter(Age >= x, Age < x + n)
  sum((1 / (1 + i))^(0:(n - 1)) * t$lx / t$lx[1])
}

# n-year term life insurance: pays $1 at end of year of death
term_insurance <- function(x, n, i) {
  t <- lt |> filter(Age >= x, Age < x + n)
  kpx <- t$lx / t$lx[1]
  sum((1 / (1 + i))^(1:n) * kpx * t$qx)
}

tibble(interest = c(0.02, 0.04, 0.06)) |>
  mutate(
    annuity_65       = map_dbl(interest, ~ annuity(65, .x)),
    cost_20k_pension = 20000 * annuity_65,
    term_premium_40  = map_dbl(interest, ~ 500000 * term_insurance(40, 20, .x) /
                                 temp_annuity(40, 20, .x))
  )
lt <- life_exp |> filter(Sex == "Male", Year == 2020) |> select(Age, qx, lx)

# Whole-life annuity: value of $1/year paid from age x until death
annuity <- function(x, i) {
  t <- lt |> filter(Age >= x)
  kpx <- t$lx / t$lx[1]                      # prob. of surviving k years
  sum((1 / (1 + i))^(0:(nrow(t) - 1)) * kpx)
}

# n-year annuity (used for paying premiums)
temp_annuity <- function(x, n, i) {
  t <- lt |> filter(Age >= x, Age < x + n)
  sum((1 / (1 + i))^(0:(n - 1)) * t$lx / t$lx[1])
}

# n-year term life insurance: pays $1 at end of year of death
term_insurance <- function(x, n, i) {
  t <- lt |> filter(Age >= x, Age < x + n)
  kpx <- t$lx / t$lx[1]
  sum((1 / (1 + i))^(1:n) * kpx * t$qx)
}

tibble(interest = c(0.02, 0.04, 0.06)) |>
  mutate(
    annuity_65       = map_dbl(interest, ~ annuity(65, .x)),
    cost_20k_pension = 20000 * annuity_65,
    term_premium_40  = map_dbl(interest, ~ 500000 * term_insurance(40, 20, .x) /
                                 temp_annuity(40, 20, .x))
  )

  # Pension cost using each year's mortality
  annuity_yr <- function(year, x = 65, i = 0.04) {
    t <- life_exp |> filter(Sex == "Male", Year == year, Age >= x)
    sum((1 / (1 + i))^(0:(nrow(t) - 1)) * t$lx / t$lx[1])
  }

tibble(Year = 1970:2021) |>
  mutate(cost_20k_pension = 20000 * map_dbl(Year, annuity_yr)) |>
  ggplot(aes(Year, cost_20k_pension)) +
  geom_line(linewidth = 1) +
  scale_y_continuous(labels = scales::dollar) +
  labs(title = "Cost of a $20k/year lifetime pension for a 65-year-old man",
       subtitle = "Based on each year's mortality rates, 4% interest",
       x = NULL, y = NULL) +
  theme_minimal()

ggsave("outputs/mortality_rates.png",  width = 8, height = 5, bg = "white")   # after chart 1
ggsave("outputs/life_expectancy.png",  width = 8, height = 5, bg = "white")   # after chart 2
ggsave("outputs/gompertz_fit.png",     width = 8, height = 5, bg = "white")   # after chart 3
ggsave("outputs/pension_cost.png",     width = 8, height = 5, bg = "white")   # after chart 4