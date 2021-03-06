step_subset <- function(parent,
                        vars = parent$vars,
                        groups = parent$groups,
                        arrange = parent$arrange,
                        i = NULL,
                        j = NULL,
                        on = character()
                        ) {

  stopifnot(is_step(parent))
  stopifnot(is.null(i) || is_expression(i) || is_step(i))
  stopifnot(is.null(j) || is_expression(j))
  stopifnot(is.character(on))

  new_step(
    parent = parent,
    vars = vars,
    groups = groups,
    arrange = arrange,
    i = i,
    j = j,
    on = on,
    implicit_copy = !is.null(i) || !is.null(j),
    class = "dtplyr_step_subset"
  )
}

# When adding a subset that contains only j, it may be possible to merge
# the previous step.
step_subset_j <- function(parent,
                          vars = parent$vars,
                          groups = parent$groups,
                          arrange = parent$arrange,
                          j = NULL) {
  if (can_merge_subset(parent)) {
    i <- parent$i
    on <- parent$on
    parent <- parent$parent
  } else {
    i <- NULL
    on <- character()
  }

  step_subset(
    parent,
    vars = vars,
    groups = groups,
    arrange = arrange,
    i = i,
    j = j,
    on = on
  )
}

can_merge_subset <- function(x) {
  # Can only merge subsets
  if (!inherits(x, "dtplyr_step_subset")) {
    return(FALSE)
  }

  # Don't need to check that groups are identical because the only
  # dplyr functions that generate expression in i are
  # filter/slice/sample/arrange/join and don't affect groups

  is.null(x$j)
}

dt_sources.dtplyr_step_subset <- function(x) {
  # TODO: need to throw error if same name refers to different tables.
  if (is_step(x$i)) {
    utils::modifyList(dt_sources(x$parent), dt_sources(x$i))
  } else {
    dt_sources(x$parent)
  }
}

dt_call.dtplyr_step_subset <- function(x, needs_copy = x$needs_copy) {
  if (is.null(x$i) && is.null(x$j)) {
    return(dt_call(x$parent))
  }

  i <- if (is_step(x$i)) dt_call(x$i) else x$i

  parent <- dt_call(x$parent, needs_copy)

  if (length(x$groups) == 0) {
    if (is.null(i) && is.null(x$j)) {
      out <- parent
    } else if (is.null(i) && !is.null(x$j)) {
      out <- call2("[", parent, , x$j)
    } else if (!is.null(i) && is.null(x$j)) {
      out <- call2("[", parent, i)
    } else {
      out <- call2("[", parent, i, x$j)
    }
  } else {
    if (is.null(i)) {
      out <- call2("[", parent, , x$j)
    } else {
      if (is.null(x$j)) {
        j <- call2("[", expr(.SD), i)
      } else {
        j <- call2("[", expr(.SD), i, x$j)
      }
      out <- call2("[", parent, , j)
    }

    out <- add_grouping_param(out, x)
  }
  if (length(x$on) > 0) {
    out$on <- call2(".", !!!syms(x$on))
    out$allow.cartesian <- TRUE
  }
  out
}

# dplyr methods -----------------------------------------------------------

#' @importFrom dplyr select
#' @export
select.dtplyr_step <- function(.data, ...) {
  vars <- tidyselect::vars_select(.data$vars, ..., .include = .data$groups)
  new_vars <- names(vars)

  if (length(vars) == 0) {
    j <- 0L
    groups <- .data$groups
  } else {
    groups <- rename_groups(.data$groups, vars)
    vars <- simplify_names(vars)
    j <- call2(".", !!!syms(vars))
  }

  out <- step_subset_j(.data, vars = new_vars, groups = character(), j = j)
  step_group(out, groups)
}


#' @importFrom dplyr summarise
#' @export
summarise.dtplyr_step <- function(.data, ...) {
  dots <- capture_dots(.data, ...)
  check_summarise_vars(dots)

  if (length(dots) == 0) {
    if (length(.data$groups) == 0) {
      out <- step_subset_j(.data, vars = character(), j = 0L)
    } else {
      # Acts like distinct on grouping vars
      out <- distinct(.data, !!!syms(.data$groups))
    }
  } else {
    out <- step_subset_j(
      .data,
      vars = union(.data$groups, names(dots)),
      j = call2(".", !!!dots)
    )
  }

  step_group(out, groups = head(.data$groups, -1))
}

#' @importFrom dplyr transmute
#' @export
transmute.dtplyr_step <- function(.data, ...) {
  dots <- capture_dots(.data, ...)
  nested <- nested_vars(.data, dots, .data$vars)

  if (!nested) {
    j <- call2(".", !!!dots)
  } else {
    assign <- Map(function(x, y) call2("<-", x, y), syms(names(dots)), dots)
    output <- call2(".", !!!syms(set_names(names(dots))))
    j <- call2("{", !!!assign, output)
  }
  step_subset_j(.data, vars = names(dots), j = j)
}

# exported onLoad
filter.dtplyr_step <- function(.data, ...) {
  dots <- capture_dots(.data, ..., .j = FALSE)

  if (length(dots) == 1 && is_symbol(dots[[1]])) {
    # Suppress data.table warning when filteirng with a logical variable
    i <- call2("(", dots[[1]])
  } else {
    i <- Reduce(function(x, y) call2("&", x, y), dots)
  }

  step_subset(.data, i = i)
}

#' @importFrom dplyr arrange
#' @export
arrange.dtplyr_step <- function(.data, ..., .by_group = FALSE) {
  dots <- capture_dots(.data, ..., .j = FALSE)
  if (.by_group) {
    dots <- c(syms(.data$groups), dots)
  }

  if (length(dots) == 0) {
    return(.data)
  }

  # Order without grouping then restore
  step <- step_subset(.data, i = call2("order", !!!dots), groups = character())
  step_group(step, groups = .data$groups)
}


#' @importFrom dplyr slice
#' @export
slice.dtplyr_step <- function(.data, ...) {
  dots <- capture_dots(.data, ..., .j = FALSE)

  if (length(dots) == 0) {
    i <- NULL
  } else if (length(dots) == 1) {
    i <- dots[[1]]
  } else {
    i <- call2("c", !!!dots)
  }

  step_subset(.data, i = i)
}

#' @importFrom dplyr sample_n
#' @export
sample_n.dtplyr_step <- function(tbl,
                                 size,
                                 replace = FALSE,
                                 weight = NULL
                                 ) {
  weight <- enexpr(weight)
  step_subset(tbl, i = sample_call(size, replace, weight))
}

#' @importFrom dplyr sample_frac
#' @export
sample_frac.dtplyr_step <- function(tbl,
                                    size = 1,
                                    replace = FALSE,
                                    weight = NULL
                                    ) {
  weight <- enexpr(weight)
  step_subset(tbl, i = sample_call(expr(.N * !!size), replace, weight))
}

sample_call <- function(size, replace = FALSE, weight = NULL) {
  call <- expr(sample(.N, !!size))

  if (replace) {
    call$replace <- TRUE
  }
  call$prob <- weight
  call
}


#' @importFrom dplyr do
#' @export
do.dtplyr_step <- function(.data, ...) {
  # This is a partial implementation, because I don't think that many
  # people are likely to use it, given that do() is marked as questioning
  # Problems:
  # * doesn't handle unnamed case
  # * doesn't set .SDcols so `.SD` will only refer to non-groups
  # * can duplicating group vars (#5)

  dots <- capture_dots(.data, ...)

  if (any(names2(dots) == "")) {
    # I can't see any way to figure out what the variables are
    abort("Unnamed do() not supported by dtplyr")
  }

  new_vars <- lapply(dots, function(x) call2(".", x))
  j <- call2(".", !!!new_vars)

  vars <- union(.data$vars, names(dots))

  step_subset_j(.data, vars = vars, j = j)
}

# helpers ------------------------------------------------------------------

rename_groups <- function(groups, vars) {
  old2new <- set_names(names(vars), vars)
  groups[groups %in% names(old2new)] <- old2new[groups]
  groups
}

simplify_names <- function(vars) {
  names(vars)[vars == names(vars)] <- ""
  vars
}

# For each expression, check if it uses any newly created variables
check_summarise_vars <- function(dots) {
  for (i in seq_along(dots)) {
    used_vars <- all_names(get_expr(dots[[i]]))
    cur_vars <- names(dots)[seq_len(i - 1)]

    if (any(used_vars %in% cur_vars)) {
      abort(paste0(
        "`", names(dots)[[i]], "` ",
        "refers to a variable created earlier in this summarise().\n",
        "Do you need an extra mutate() step?"
      ))
    }
  }
}
