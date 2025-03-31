package main

import (
	"encoding/base64"
	"encoding/json"
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"strings"

	tmdb "github.com/cyruzin/golang-tmdb"
	"github.com/spf13/cobra"
)

// SearchResult represents a single search result returned by the CLI.
type SearchResult struct {
	ID                int64  `json:"id"`
	Type              string `json:"type"`
	FullTitle         string `json:"full_title"`
	OriginalTitle     string `json:"original_title"`
	ReleaseDate       string `json:"release_date"`
	Overview          string `json:"overview"`
	SmallPosterBase64 string `json:"small_poster_base64"`
	LargePosterLink   string `json:"large_poster_link"`
}

func main() {
	var apiKey string

	rootCmd := &cobra.Command{
		Use:   "tmdbclientdataprovider",
		Short: "CLI app to fetch data from TMDB",
		PersistentPreRun: func(cmd *cobra.Command, args []string) {
			// If no API key is provided via flag, try to get it from environment
			if apiKey == "" {
				apiKey = os.Getenv("TMDB_API_KEY")
				if apiKey == "" && cmd.Name() != "help" {
					log.Fatal("API key not provided. Use --api-key flag or set TMDB_API_KEY environment variable")
				}
			}
		},
	}

	// Add global API key flag to the root command
	rootCmd.PersistentFlags().StringVar(&apiKey, "api-key", "", "TMDB API key")

	// Add the search command with reference to the API key.
	rootCmd.AddCommand(searchCmd(&apiKey))

	// Execute the root command.
	if err := rootCmd.Execute(); err != nil {
		fmt.Println(err)
		os.Exit(1)
	}
}

// searchCmd returns the search command definition.
func searchCmd(apiKey *string) *cobra.Command {
	cmd := &cobra.Command{
		Use:   "search [query]",
		Short: "Search for a movie or TV show on TMDB",
		Args:  cobra.MinimumNArgs(1),
		Run: func(cmd *cobra.Command, args []string) {
			runSearch(*apiKey, args)
		},
	}

	return cmd
}

// runSearch executes the search command.
func runSearch(apiKey string, args []string) {
	// Join the provided args to form the query string.
	query := strings.Join(args, " ")

	// Initialize the TMDB client.
	tmdbClient, err := tmdb.Init(apiKey)
	if err != nil {
		log.Fatalf("Error initializing TMDB client: %v", err)
	}

	// Prepare search parameters (if needed, you can add options).
	params := map[string]string{}

	// Updated call: Pass the query as first argument.
	searchResp, err := tmdbClient.GetSearchMulti(query, params)
	if err != nil {
		log.Fatalf("Error searching TMDB: %v", err)
	}

	var searchResults []SearchResult

	// Loop over each result.
	// (Make sure to check the actual field name in the SearchMulti struct – this example assumes it has a Results field)
	for _, item := range searchResp.Results {
		var sr SearchResult

		// Extract the ID (assuming item.ID is a number)
		sr.ID = item.ID

		// Determine media type and extract titles/dates.
		// This assumes that item has a MediaType field and different fields for movies and TV.
		sr.Type = item.MediaType
		switch sr.Type {
		case "movie":
			sr.FullTitle = item.Title
			sr.OriginalTitle = item.OriginalTitle
			sr.ReleaseDate = item.ReleaseDate
		case "tv":
			sr.FullTitle = item.Name
			sr.OriginalTitle = item.OriginalName
			sr.ReleaseDate = item.FirstAirDate
		default:
			// Fallback if type is not movie or tv.
			sr.FullTitle = item.Title
			sr.OriginalTitle = item.OriginalTitle
			sr.ReleaseDate = item.ReleaseDate
		}

		sr.Overview = item.Overview

		// Process poster images if available.
		if item.PosterPath != "" {
			smallPosterURL := "https://image.tmdb.org/t/p/w154" + item.PosterPath
			if encoded, err := fetchImageBase64(smallPosterURL); err == nil {
				sr.SmallPosterBase64 = encoded
			}
			sr.LargePosterLink = "https://image.tmdb.org/t/p/w500" + item.PosterPath
		}

		searchResults = append(searchResults, sr)
	}

	// Marshal the results into JSON.
	output, err := json.MarshalIndent(searchResults, "", "  ")
	if err != nil {
		log.Fatalf("Error marshaling results: %v", err)
	}
	fmt.Println(string(output))
}

// fetchImageBase64 retrieves the image from the given URL and returns it as a base64-encoded string.
func fetchImageBase64(url string) (string, error) {
	resp, err := http.Get(url)
	if err != nil {
		return "", err
	}
	defer resp.Body.Close()

	if resp.StatusCode != http.StatusOK {
		return "", fmt.Errorf("failed to fetch image: %s", resp.Status)
	}

	imgData, err := io.ReadAll(resp.Body) // using io.ReadAll instead of ioutil.ReadAll
	if err != nil {
		return "", err
	}

	encoded := base64.StdEncoding.EncodeToString(imgData)
	return encoded, nil
}
