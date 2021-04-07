
#' conditional_filter
#'
#' @param condition Test condition; typically we check the length of one of the
#'   Shiny inputs
#' @param success Desired return when `condition` is satisfied; typically a
#'   filter statement based on input in `condition`
#'
#' @return Statement to be used to filter the data, to go inside a
#'   dplyr::filter() call
#'
#' @export
#'
#' @description Simple helper function that allows filtering the data on
#'   multiple parameters, without the need for multiple step-wise filters.
#'
conditional_filter <- function(condition, success) {
  if (condition) {
    return(success)
  } else {
    return(TRUE)
  }
}




#' not_NA
#'
#' @param vector Input vector to be cleaned
#'
#' @return Vector stripped of any NA values.
#'
#' @export
#'
#' @description Simple function to remove NA values from input vector, without
#'   the extra class elements included in na.omit(), which can cause errors in
#'   other functions
#'
not_NA <- function(vector) {
  vector <- vector[!is.na(vector)]
  return(vector)
}




#' create_selectInput
#'
#' @param column_name Name of the column to filter on; used to name the input
#'   and select the appropriate column
#' @param tab Name of the tab into which this UI object is inserted, used to
#'   build the ID
#'
#' @return Shiny `selectInput` object to be used in UI creation
#'
#' @export
#'
create_selectInput <- function(column_name, tab) {
  selectInput(
    inputId  = paste0(tab, "_", janitor::make_clean_names(column_name), "_input"),
    label    = column_name,
    choices  = unique(not_NA(full_data[[column_name]])),
    multiple = TRUE
  )
}




#' map_genes
#'
#' @param gene_list Character vector of input genes
#' @param gene_table Tibble of input genes; one column with name "input_genes"
#'
#' @return Table of genes, including the user's input and the other two ID types
#'   used in the enrichment analysis
#'
#' @export
#'
#' @description Detects input ID type, and maps using static biomaRt data.
#'   Assumes input comes from the app, and hence is a data frame of one column
#'   named "input_genes".
#'
map_genes <- function(gene_list, gene_table) {

  message("\nMapping genes...")
  mapped_table <- NULL

  if (str_detect(gene_list[1], "^ENSG[0-9]*$")) {
    mapped_table <- left_join(
      gene_table,
      biomart_table,
      by = c("input_genes" = "ensembl_gene_id")
    ) %>%
      dplyr::rename("ensembl_gene_id" = input_genes)
    attr(mapped_table, "id_type") <- "Ensembl"

  } else if (str_detect(gene_list[1], "^[0-9]*$")) {
    mapped_table <- left_join(
      gene_table,
      biomart_table,
      by = c("input_genes" = "entrez_gene_id")
    ) %>%
      dplyr::rename("entrez_gene_id" = input_genes)
    attr(mapped_table, "id_type") <- "Entrez"

  } else {
    mapped_table <- left_join(
      gene_table,
      biomart_table,
      by = c("input_genes" = "hgnc_symbol")
    ) %>%
      dplyr::rename("hgnc_symbol" = input_genes)
    attr(mapped_table, "id_type") <- "HGNC"
  }

  message("Done.\n")
  return(mapped_table)
}




#' test_enrichment
#'
#' @param gene_table Data frame or tibble of genes, with standard column names
#' as output by `map_genes()`
#'
#' @return List of length two, for ReactomePA and EnrichR result. Each is a data
#' frame, with the attribute `num_input_genes`.
#'
#' @export
#'
#' @description Performed pathway enrichment using ReactomePA, and enrichR (GO
#'   and MSigDB sources).
#'
test_enrichment <- function(gene_table) {

  # Create safe versions of enrichment functions that return NULL on error
  reactomePA_safe <- possibly(ReactomePA::enrichPathway, otherwise = NULL)
  enrichR_safe    <- possibly(enrichR::enrichr, otherwise = NULL)

  # Clean inputs by removing NA's
  input_entrez <- not_NA(gene_table[["entrez_gene_id"]])
  input_hgnc   <- not_NA(gene_table[["hgnc_symbol"]])


  # ReactomePA
  message("\nRunning ReactomePA...")
  reactomePA_result_1 <- reactomePA_safe(
    gene = input_entrez
  )

  if (is.null(reactomePA_result_1)) {
    reactomePA_result_2 <- NULL
  } else {
    reactomePA_result_2 <- reactomePA_result_1@result %>%
      filter(p.adjust <= 0.05) %>%
      janitor::clean_names()

    attr(reactomePA_result_2, "num_input_genes") <- length(input_entrez)
  }


  # EnrichR
  message("Running enrichR...")
  enrichR_result <- enrichR_safe(
    genes = input_hgnc,
    databases = c(
      "MSigDB_Hallmark_2020",
      "GO_Molecular_Function_2018",
      "GO_Cellular_Component_2018",
      "GO_Biological_Process_2018"
    )
  ) %>%
    bind_rows(.id = "database") %>%
    janitor::clean_names() %>%
    filter(adjusted_p_value <= 0.05)

  attr(enrichR_result, "num_input_genes") <- length(input_hgnc)

  message("Done.\n")
  return(list(
    "ReactomePA" = reactomePA_result_2,
    "EnrichR"    = enrichR_result
  ))
}



#' make_success_message
#'
#' @param input_type Type of gene ID provided as input
#' @param mapped_data Table of mapped genes
#'
#' @return UI elements for success message
#'
#' @export
#'
#' @description Conditionally creates and returns the appropriate UI element to
#'   be inserted into the sidebar, informing the user about their input and
#'   mapped genes. Placed into a separate function to make the main app code
#'   cleaner.
#'
make_success_message <- function(mapped_data) {

  input_type <- attr(mapped_data, "id_type")

  if (input_type == "Ensembl") {
    tags$p(
      "Success! Your ",
      length(unique(mapped_data$ensembl_gene_id)),
      " unique Ensembl genes were mapped to ",
      length(unique(mapped_data$hgnc_symbol)),
      " HGNC symbols, and ",
      length(unique(mapped_data$entrez_gene_id)),
      " Entrez IDs. Use the buttons below to download your results."
    )

  } else if (input_type == "Entrez") {
    tags$p(
      "Success! Your ",
      length(unique(mapped_data$entrez_gene_id)),
      " unique Entrez genes were mapped to ",
      length(unique(mapped_data$hgnc_symbol)),
      " HGNC symbols, and ",
      length(unique(mapped_data$ensembl_gene_id)),
      " Ensembl IDs. Use the buttons below to download your results."
    )

  } else if (input_type == "HGNC") {
    tags$p(
      "Success! Your ",
      length(unique(mapped_data$hgnc_symbol)),
      " unique HGNC symbols were mapped to ",
      length(unique(mapped_data$entrez_gene_id)),
      " Entrez IDs, and ",
      length(unique(mapped_data$ensembl_gene_id)),
      " Ensembl IDs. Use the buttons below to download your results."
    )

  } else {
    tags$p(
      "It seems there was a problem with mapping your input genes. ",
      "Please check your inputs and try again."
    )
  }
}