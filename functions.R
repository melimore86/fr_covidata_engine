verifyLuhn <- function(input, base_encoding = 16, factor = 2) {
  # https://en.wikipedia.org/wiki/Luhn_mod_N_algorithm
  # assumes input is hexadecimal
  # assumes input is in format 1-12345-01-X
  # <location_id>-<record_id>-<visit_id>-<check_digit>
  unpacked_input = strsplit(input, '-')
  check_digit = strtoi((unpacked_input[[1]][4]), base = base_encoding)
  # concatenate record_id and visit_id
  raw_number = paste(unpacked_input[[1]][2], unpacked_input[[1]][3], sep = '')
  
  # split the string, convert it to a list, convert digits to decimal
  digits = strtoi(unlist(strsplit(raw_number, "")), base = base_encoding)
  
  # reverse the string
  digits = digits[length(digits):1]
  
  # multiply every other digit by the proper factor
  to_mult = seq(1, length(digits), 2)
  digits[to_mult] = as.numeric(digits[to_mult]) * factor
  
  # sum the digits of the "addend" as expressed in base base_encoding
  addends = floor(digits / base_encoding) + (digits %% base_encoding)
  
  # returns a boolean
  return( sum(c(addends, strtoi(check_digit))) %% base_encoding == 0 )
}