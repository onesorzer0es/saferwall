// Copyright 2021 Saferwall. All rights reserved.
// Use of this source code is governed by Apache v2 license
// license that can be found in the LICENSE file.

package main

import (
	"encoding/json"
	"errors"
	"os"
	"os/signal"
	"path"
	"syscall"
	"time"

	"github.com/minio/minio-go/v6"
	nsq "github.com/nsqio/go-nsq"
	"github.com/saferwall/saferwall/pkg/utils"
	log "github.com/sirupsen/logrus"
	"github.com/spf13/viper"
)

var (
	minioClient     *minio.Client
	backendEndpoint string
	backendToken    string
	contextLogger   *log.Entry
)

// File scan progress status.
const (
	queued     = iota
	processing = iota
	finished   = iota
)

// NoopNSQLogger allows us to pipe NSQ logs to dev/null
// The default NSQ logger is great for debugging, but did
// not fit our normally well structured JSON logs. Luckily
// NSQ provides a simple interface for injecting your own
// logger.
type NoopNSQLogger struct{}

// Output allows us to implement the nsq.Logger interface
func (l *NoopNSQLogger) Output(calldepth int, s string) error {
	log.Info(s)
	return nil
}

// MessageHandler adheres to the nsq.Handler interface.
// This allows us to define our own custome handlers for
// our messages. Think of these handlers much like you would
// an http handler.
type MessageHandler struct{}

// HandleMessage is the only requirement needed to fulfill the
// nsq.Handler interface. This where you'll write your message
// handling logic.
func (h *MessageHandler) HandleMessage(m *nsq.Message) error {
	if len(m.Body) == 0 {
		// returning an error results in the message being re-enqueued
		// a REQ is sent to nsqd
		return errors.New("body is blank re-enqueue message")
	}

	sha256 := string(m.Body)

	// Always include sha256 in our context logger.
	contextLogger = log.WithFields(log.Fields{"sha256": sha256})
	contextLogger.Info("Start scanning ...")

	// Set the file status to `processing`.
	var err error
	res := result{}
	res.Status = processing

	// Marshell results.
	var buff []byte
	if buff, err = json.Marshal(res); err != nil {
		contextLogger.Errorf("Failed to json marshal object: %v", err)
		return err
	}

	// Update document.
	err = updateDocument(sha256, buff)
	if err != nil {
		contextLogger.Errorf("Failed to update document for file %s, reason: %v",
			sha256, err)
		return err
	}

	// Download the sample.
	bucketName := viper.GetString("minio.spacename")
	filePath := path.Join("/samples", sha256)
	b, err := utils.Download(minioClient, bucketName, filePath, sha256)
	if err != nil {
		contextLogger.Errorf("Failed to download file %s", sha256)
		return err
	}

	// Static scanning.
	res = staticScan(sha256, filePath, b)

	// Multiav scanning.
	multiavScanResults := multiAvScan(filePath)
	res.MultiAV = map[string]interface{}{}
	res.MultiAV["last_scan"] = multiavScanResults

	// Extract tags.
	res.getTags()

	//

	// Analysis finished
	res.Status = finished
	now := time.Now().UTC()
	res.LastScanned = &now

	// Marshell results.
	buff, err = json.Marshal(res)
	if err != nil {
		contextLogger.Errorf("Failed to json marshal object: %v", err)
		return err
	}

	// Get ML classification results.
	// http web api call as input (json)

	// Get ranked strings results.
	// http web api call as input (json)

	// Update document.
	err = updateDocument(sha256, buff)
	if err != nil {
		contextLogger.Errorf("Failed to update document: %v", err)
		return err
	}

	// Delete the file from the network share.
	if utils.Exists(filePath) {
		if err = utils.DeleteFile(filePath); err != nil {
			log.Errorf("Failed to delete file path %s", filePath)
		}
	}

	// Returning nil signals to the consumer that the message has
	// been handled with success. A FIN is sent to nsqd.
	return nil
}

func main() {

	// Log as JSON instead of the default ASCII formatter.
	log.SetFormatter(&log.JSONFormatter{})

	// Load consumer config.
	loadConfig()

	// Setup logging.
	setupLogging()

	// Set backend API address.
	backendEndpoint = viper.GetString("backend.address") + "/v1/files/"

	// Login to backend.
	var err error
	backendToken, err = login()
	if err != nil {
		log.Fatalf("Failed to get auth token: %v", err)
	}

	// Get an minio client instance.
	accessKey := viper.GetString("minio.accesskey")
	secKey := viper.GetString("minio.seckey")
	endpoint := viper.GetString("minio.endpoint")
	ssl := viper.GetBool("minio.ssl")
	minioClient, err = minio.New(endpoint, accessKey, secKey, ssl)
	if err != nil {
		log.Fatalf("Failed to connect to object storage: %v", err)
	}

	// The default config settings provide a pretty good starting point for
	// our new consumer.
	config := nsq.NewConfig()

	// Maximum number of times this consumer will attempt to process a message
	// before giving up.
	config.MaxAttempts = 2

	// Maximum number of messages to allow in flight (concurrency knob).
	config.MaxInFlight = 1

	// The server-side message timeout for messages delivered to this client.
	config.MsgTimeout = time.Duration(2 * time.Minute)

	// Create a NewConsumer with the name of our topic, the channel, and our config.
	consumer, err := nsq.NewConsumer("scan", "file", config)
	if err != nil {
		log.Errorln("Could not create consumer")
	}

	// Here we set the logger to our NoopNSQLogger to quiet down the default logs.
	// At Reverb we use a custom structured logging format so we'll take the
	// logging from here.
	consumer.SetLogger(
		&NoopNSQLogger{},
		nsq.LogLevelError,
	)

	// Injects our handler into the consumer. You'll define one handler
	// per consumer, but you can have as many concurrently running handlers
	// as specified by the second argument. If your MaxInFlight is less
	// than your number of concurrent handlers you'll starve your workers
	// as there will never be enough in flight messages for your worker pool
	consumer.AddConcurrentHandlers(
		&MessageHandler{},
		1,
	)

	// Our consumer will discover where topics are located by our three
	// nsqlookupd instances The application will periodically poll
	// these nqslookupd instances to discover new nodes or drop unhealthy
	// producers.
	nsqlds := viper.GetStringSlice("nsq.lookupd")
	if err := consumer.ConnectToNSQLookupds(nsqlds); err != nil {
		log.Fatal(err)
	}

	log.Info("Connected to nsqlookupd")

	// Let's allow our queues to drain properly during shutdown.
	// We'll create a channel to listen for SIGINT (Ctrl+C) to signal
	// to our application to gracefully shutdown.
	shutdown := make(chan os.Signal, 2)
	signal.Notify(shutdown, syscall.SIGINT)

	// This is our main loop. It will continue to read off of our nsq
	// channel until either the consumer dies or our application is signaled
	// to stop.
	for {
		select {
		case <-consumer.StopChan:
			return // uh oh consumer disconnected. Time to quit.
		case <-shutdown:
			// Synchronously drain the queue before falling out of main
			consumer.Stop()
		}
	}
}
